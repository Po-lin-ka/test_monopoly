"""Без Oracle: ошибки драйвера и поведение Qt при восстановлении связи."""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
import unittest
import time
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import oracledb
from PySide6.QtTest import QTest
from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import QApplication

from app.db import ConnectionLost, Database, DatabaseError
from app.service import GameService
from app.snapshot import ReconnectThread
from app.ui import Window


def oracle_error(code, message):
    return oracledb.OperationalError(SimpleNamespace(full_code=code, message=message, isrecoverable=False))


class DatabaseTests(unittest.TestCase):
    def setUp(self):
        self.db = Database.__new__(Database)
        self.conn = self.db.connection = MagicMock()
        self.conn.is_healthy.return_value = True

    def test_original_error_survives_failed_rollback_and_close(self):
        original = oracle_error('DPY-4011', 'original network failure')
        self.conn.cursor.return_value.callproc.side_effect = original
        self.conn.rollback.side_effect = oracle_error('DPY-1001', 'rollback failed')
        self.conn.cursor.return_value.close.side_effect = oracle_error('DPY-1001', 'close failed')
        with self.assertRaisesRegex(ConnectionLost, 'original network failure') as caught:
            self.db.callproc('monopoly.end_turn', [1])
        self.assertIs(caught.exception.__cause__, original)
        self.conn.cursor.return_value.callproc.assert_called_once()
        self.conn.commit.assert_not_called()

    def test_uncertain_commit_never_replays_command(self):
        self.conn.commit.side_effect = oracle_error('DPY-4024', 'commit timed out')
        with self.assertRaises(ConnectionLost):
            self.db.callproc('monopoly.roll_and_move', [1])
        self.conn.cursor.return_value.callproc.assert_called_once()
        self.conn.commit.assert_called_once()

    def test_rule_error_remains_database_error(self):
        self.conn.cursor.return_value.callproc.side_effect = oracle_error('ORA-20001', 'rule violation')
        with self.assertRaises(DatabaseError) as caught:
            self.db.callproc('monopoly.end_turn', [1])
        self.assertNotIsInstance(caught.exception, ConnectionLost)
        self.conn.rollback.assert_called_once()

    def test_direct_service_cursor_errors_are_wrapped(self):
        self.conn.cursor.return_value.execute.side_effect = oracle_error('DPY-4011', 'read failed')
        with self.assertRaises(ConnectionLost):
            GameService(self.db).participant(1, 1)

    def test_snapshot_cleanup_preserves_original_error(self):
        self.conn.cursor.return_value.callproc.side_effect = oracle_error('DPY-4011', 'snapshot failed')
        self.conn.rollback.side_effect = oracle_error('DPY-1001', 'rollback failed')
        self.conn.cursor.return_value.close.side_effect = oracle_error('DPY-1001', 'close failed')
        with self.assertRaisesRegex(ConnectionLost, 'snapshot failed'):
            GameService(self.db).snapshot(1)

    def test_closed_connection_and_reconnect_limits(self):
        self.db.close()
        with self.assertRaises(ConnectionLost):
            self.db.callproc('monopoly.end_turn', [1])
        with patch('app.db.oracledb.connect', return_value=self.conn) as connect:
            self.db.reconnect()
        self.assertGreater(connect.call_args.kwargs['tcp_connect_timeout'], 0)
        self.assertGreater(self.conn.call_timeout, 0)


class WindowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.application = QApplication.instance() or QApplication([])

    def setUp(self):
        with patch('app.ui.Database'):
            self.window = Window()
        self.window.timer.stop()
        self.window.local_timer.stop()
        self.window.alert = MagicMock()
        self.window.s = MagicMock()
        self.window.part, self.window.game = 11, 22
        self.window.state_row = {'код_статуса_игры': 'АКТИВНА'}

    def tearDown(self):
        self.window.snapshot_thread = None
        self.window.reconnect_thread = None
        self.window.close()
        self.window.deleteLater()

    def test_loss_blocks_commands_without_replaying(self):
        operation = MagicMock(side_effect=ConnectionLost('lost'))
        self.window.act(operation)
        self.assertTrue(self.window.connection_lost)
        self.assertFalse(self.window.stack.isEnabled())
        self.window.act(operation)
        operation.assert_called_once()
        self.window.alert.assert_not_called()

    def test_minimize_does_not_disconnect(self):
        self.window.showMinimized()
        self.application.processEvents()
        self.window.s.disconnect.assert_not_called()
        self.assertEqual(self.window.part, 11)

    def test_close_while_worker_busy_is_deferred(self):
        self.window.snapshot_thread = MagicMock()
        self.window.snapshot_thread.isRunning.return_value = True
        event = QCloseEvent()
        self.window.closeEvent(event)
        self.assertFalse(event.isAccepted())
        self.window.s.disconnect.assert_not_called()
        self.window.snapshot_thread.isRunning.return_value = False
        event = QCloseEvent()
        self.window.closeEvent(event)
        self.assertTrue(event.isAccepted())
        self.window.s.disconnect.assert_called_once_with(11)

    def test_normal_close_sends_exit_once(self):
        self.window.disconnect_on_window_close()
        self.window.disconnect_on_window_close()
        self.window.s.disconnect.assert_called_once_with(11)

    def test_close_offline_relies_on_presence(self):
        self.window.connection_lost = True
        self.window.disconnect_on_window_close()
        self.window.s.disconnect.assert_not_called()

    def test_recovery_transfers_connection_before_applying_state(self):
        database, snapshot = MagicMock(), {'state': []}
        self.window.connection_lost = True
        self.window.reconnect_thread = SimpleNamespace(
            database=database, snapshot=snapshot, error=None, arguments=(11, 0, 0))
        self.window.apply_snapshot = MagicMock()
        self.window.reconnect_finished()
        self.assertIs(self.window.db, database)
        self.assertIs(self.window.s.db, database)
        self.assertFalse(self.window.connection_lost)
        self.window.apply_snapshot.assert_called_once_with(snapshot)

    def test_background_recovery_completes_through_qt_signals(self):
        self.window.part = None
        self.window.report_error(ConnectionLost('lost'))
        with patch('app.snapshot.Database') as db, patch('app.snapshot.GameService') as service:
            self.window.poll()
            deadline = time.monotonic() + 5
            while self.window.reconnecting and time.monotonic() < deadline:
                QTest.qWait(10)
            self.assertFalse(self.window.reconnecting)
            self.assertFalse(self.window.connection_lost)
            self.assertIs(self.window.db, db.return_value)
            service.return_value.list_games.assert_called_once()
            self.assertTrue(self.window.stack.isEnabled())

    def test_failed_recovery_keeps_actions_blocked(self):
        self.window.report_error(ConnectionLost('lost'))
        self.window.reconnect_thread = SimpleNamespace(error=ConnectionLost('still lost'))
        self.window.reconnect_finished()
        self.assertTrue(self.window.connection_lost)
        self.assertFalse(self.window.stack.isEnabled())

    def test_departed_player_is_not_returned_to_board(self):
        self.window.return_to_rooms = MagicMock()
        self.window.update_action_log = MagicMock()
        self.window.apply_snapshot({
            'state': [{'id_игры': 22, 'код_статуса_игры': 'АКТИВНА'}],
            'players': [{'id_участника': 11, 'код_статуса_участника': 'ПОКИНУЛ'}],
            'cells': [], 'ownerships': [], 'actions': [], 'chat': [],
        })
        self.window.return_to_rooms.assert_called_once()
        self.window.alert.assert_called_once()


class WorkerTests(unittest.TestCase):
    def test_recovery_only_reads_snapshot(self):
        with patch('app.snapshot.Database') as db, patch('app.snapshot.GameService') as service:
            worker = ReconnectThread(11, 7, 3)
            worker.run()
            service.return_value.snapshot.assert_called_once_with(11, 7, 3)
            self.assertEqual([call[0] for call in service.return_value.method_calls], ['snapshot'])
            self.assertIs(worker.database, db.return_value)

    def test_failed_recovery_closes_connection(self):
        with patch('app.snapshot.Database') as db, patch('app.snapshot.GameService') as service:
            service.return_value.snapshot.side_effect = ConnectionLost('lost')
            worker = ReconnectThread(11, 0, 0)
            worker.run()
            self.assertIsNone(worker.database)
            self.assertIsInstance(worker.error, ConnectionLost)
            db.return_value.close.assert_called_once()


if __name__ == '__main__':
    unittest.main()
