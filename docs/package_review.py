"""Build the runnable reviewer bundle without local credentials or environments."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
files = []
for folder in ('app', 'database'):
    files.extend(
        p for p in (root / folder).rglob('*')
        if p.is_file() and '__pycache__' not in p.parts
        and p.suffix != '.pyc' and not p.name.startswith('uninstall_')
    )
files.extend(root / name for name in (
    'requirements.txt', '1_Подготовить_окружение.bat', '2_Запустить_игру.bat',
    'ПРОВЕРЯЮЩИМ.md',
))
config = '''# Укажите параметры рабочего подключения Oracle. У всех игроков они одинаковые.
ORACLE_USER="ВАШ_ПОЛЬЗОВАТЕЛЬ_ORACLE_DSN"
ORACLE_PASSWORD="ВАШ_ПАРОЛЬ_ORACLE"
ORACLE_DSN="(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=10.22.10.41)(PORT=1521))(CONNECT_DATA=(SID=ORCL)))"
POLL_INTERVAL_MS=2000
CONNECT_TIMEOUT_SECONDS=5
CALL_TIMEOUT_MS=5000
'''
output = root / 'Передать_проверяющим.zip'
temporary = output.with_suffix('.tmp')
with ZipFile(temporary, 'w', ZIP_DEFLATED) as archive:
    for path in sorted(files):
        archive.write(path, str(Path('Monopoly') / path.relative_to(root)))
    archive.writestr('Monopoly/.env', config.encode('utf-8'))
with ZipFile(temporary) as archive:
    assert archive.testzip() is None
    names = archive.namelist()
    assert archive.read('Monopoly/.env') == config.encode('utf-8')
    assert not any(
        part in ('.git', '.venv', '.venv-windows', '__pycache__', 'launcher')
        for name in names for part in Path(name).parts
    )
    assert not any(Path(n).name in ('connection.json', 'connection_for_player2.json') for n in names)
    for name in names:
        if name.endswith('.py'):
            compile(archive.read(name), name, 'exec')
    for name in ('1_Подготовить_окружение.bat', '2_Запустить_игру.bat'):
        data = archive.read('Monopoly/' + name)
        assert b'\r\n' in data
        assert b'\n' not in data.replace(b'\r\n', b'')
temporary.replace(output)
print(f'Packaged {len(files) + 1} files; ZIP and Python syntax checked: {output}')
