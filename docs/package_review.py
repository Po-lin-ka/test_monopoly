"""Build a review bundle using an allowlist; credentials and local venvs are excluded."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
files = []
for folder in ('app', 'database', 'launcher'):
    files.extend(p for p in (root/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.pyc')
files.extend(root/name for name in (
    'requirements.txt', '1_Создать_базу_и_играть.bat', '2_Подключиться_и_играть.bat',
    'ПРОВЕРЯЮЩИМ.md', 'ПИМ_Упрощённая_монополия.docx', 'ПИМ_Упрощённая_монополия.pdf',
))
with ZipFile(root/'Передать_проверяющим.zip', 'w', ZIP_DEFLATED) as archive:
    for path in sorted(files):
        archive.write(path, str(Path('Monopoly')/path.relative_to(root)))
with ZipFile(root/'Передать_проверяющим.zip') as archive:
    assert archive.testzip() is None
    assert not any(Path(n).name in ('.env', 'connection.json', 'connection_for_player2.json') for n in archive.namelist())
print(f'Packaged {len(files)} files without local credentials')
