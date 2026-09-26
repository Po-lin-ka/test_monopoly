import importlib.util
import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import MagicMock, Mock, patch

SPEC = importlib.util.spec_from_file_location('windows_launcher', Path(__file__).resolve().parents[1] / 'launcher/windows.py')
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)


class LauncherTests(unittest.TestCase):
    def cursor(self, objects, counts=(12, 10)):
        cur = Mock()
        cur.fetchall.return_value = objects
        cur.fetchone.side_effect = [(n,) for n in counts]
        return cur

    def objects(self):
        return [(name, kind, 'VALID') for name, kind in launcher.expected_objects()]

    def test_empty_schema_ignores_unrelated_objects(self):
        self.assertEqual(launcher.schema_state(self.cursor([('OTHER', 'TABLE', 'VALID')])), 'empty')

    def test_existing_complete_schema_is_reused(self):
        self.assertEqual(launcher.schema_state(self.cursor(self.objects())), 'ready')

    def test_partial_or_invalid_schema_is_not_reinstalled(self):
        rows = self.objects()
        for objects in [rows[:-1], [(n, t, 'INVALID' if t == 'PACKAGE BODY' else s) for n,t,s in rows]]:
            self.assertEqual(launcher.schema_state(self.cursor(objects)), 'partial')

    def test_conflicting_object_type_blocks_install(self):
        self.assertEqual(launcher.schema_state(self.cursor([('ПОЛЬЗОВАТЕЛИ', 'VIEW', 'VALID')])), 'partial')

    def test_incomplete_seed_data_blocks_start(self):
        self.assertEqual(launcher.schema_state(self.cursor(self.objects(), (11,10))), 'partial')

    def test_password_round_trip_preserves_shell_metacharacters(self):
        data = dict(zip(launcher.KEYS, ('КС2318_03', 'p%&!^"\'\\$ пароль', 'localhost:1521/ORCL')))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'profile.json'
            launcher.save_profile(path, data)
            self.assertEqual(launcher.read_profile(path), data)
            path.write_text(json.dumps({'ORACLE_USER':'user'}))
            with self.assertRaises(ValueError): launcher.read_profile(path)

    def test_join_without_file_never_connects_or_installs(self):
        with tempfile.TemporaryDirectory() as directory:
            missing=Path(directory)/'missing.json'
            with patch.object(launcher,'PROFILE',missing), patch.object(launcher,'TRANSFER',missing):
                with self.assertRaisesRegex(RuntimeError,'connection_for_player2'):
                    launcher.run('join')

    def test_roles_install_only_empty_host_schema(self):
        profile = dict(zip(launcher.KEYS, ('test', 'secret', 'test:1521/service')))
        for role, state in [('host', 'ready'), ('host', 'partial'),
                            ('host', 'empty'), ('join', 'empty'), ('join', 'ready')]:
            with self.subTest(role=role, state=state), tempfile.TemporaryDirectory() as directory:
                path = Path(directory)/'connection.json'
                transfer = Path(directory)/'connection_for_player2.json'
                launcher.save_profile(path, profile)
                database = MagicMock()
                install = Mock()
                modules = {'app.db': types.SimpleNamespace(Database=Mock(return_value=database)),
                           'database.install': types.SimpleNamespace(install=install)}
                with patch.object(launcher, 'PROFILE', path), patch.object(launcher, 'TRANSFER', transfer), \
                     patch.dict('sys.modules', modules), patch.dict('os.environ', {}, clear=False), \
                     patch.object(launcher, 'schema_state', side_effect=[state, 'ready']), \
                     patch.object(launcher.subprocess, 'call', return_value=0) as launch, patch('builtins.print'):
                    if state == 'partial' or (role == 'join' and state == 'empty'):
                        with self.assertRaises(RuntimeError): launcher.run(role)
                        launch.assert_not_called()
                    else:
                        self.assertEqual(launcher.run(role), 0)
                        launch.assert_called_once()
                    self.assertEqual(install.call_count, int(role == 'host' and state == 'empty'))

    def test_bats_use_crlf_and_separate_roles(self):
        root=Path(__file__).resolve().parents[1]
        for name,role in [('1_Создать_базу_и_играть.bat',b'host'),('2_Подключиться_и_играть.bat',b'join')]:
            data=(root/name).read_bytes()
            self.assertIn(b'windows.py" '+role,data)
            self.assertNotIn(b'\n',data.replace(b'\r\n',b''))
            self.assertNotIn(b'database.install',data)

if __name__ == '__main__': unittest.main()
