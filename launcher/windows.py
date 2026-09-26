"""Two Windows entry points; no secrets are embedded in the distribution."""
from __future__ import annotations

import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / 'connection.json'
TRANSFER = ROOT / 'connection_for_player2.json'
VENV = ROOT / '.venv-windows'
PYTHON = VENV / 'Scripts' / 'python.exe'
KEYS = ('ORACLE_USER', 'ORACLE_PASSWORD', 'ORACLE_DSN')


def read_profile(path):
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    if not isinstance(data, dict) or any(not isinstance(data.get(k), str) or not data[k].strip() for k in KEYS):
        raise ValueError('В файле подключения должны быть непустые логин, пароль и DSN Oracle.')
    return {k: data[k] for k in KEYS}


def save_profile(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def ask_profile():
    print('Данные берутся из рабочего подключения SQL Developer. Пароль при вводе скрыт.')
    user = input('Логин Oracle: ').strip()
    password = getpass.getpass('Пароль Oracle: ')
    host = input('Сервер Oracle [10.22.10.41]: ').strip() or '10.22.10.41'
    port = input('Порт [1521]: ').strip() or '1521'
    kind = input('Тип подключения: 1 — SID, 2 — Service name [1]: ').strip() or '1'
    name = input('SID / Service name [ORCL]: ').strip() or 'ORCL'
    if not user or not password or kind not in ('1', '2'):
        raise ValueError('Заполните логин и пароль и выберите тип 1 или 2.')
    if not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise ValueError('Некорректный порт Oracle.')
    if any(c in host + name for c in '()=\r\n'):
        raise ValueError('В адресе и имени базы не допускаются скобки, знак = и перенос строки.')
    field = 'SID' if kind == '1' else 'SERVICE_NAME'
    dsn = f'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST={host})(PORT={port}))(CONNECT_DATA=({field}={name})))'
    return dict(zip(KEYS, (user, password, dsn)))


def expected_objects():
    tables = (ROOT / 'database/02_create_tables.sql').read_text(encoding='utf-8')
    expected = {(name, 'TABLE') for name in re.findall(r'CREATE TABLE "([^"]+)"', tables)}
    expected |= {(name, 'INDEX') for name in re.findall(r'CREATE (?:UNIQUE )?INDEX "([^"]+)"', tables)}
    return expected | {('NUMBER_LIST', 'TYPE'), ('MONOPOLY', 'PACKAGE'), ('MONOPOLY', 'PACKAGE BODY')}


def schema_state(cursor):
    expected = expected_objects()
    cursor.execute('SELECT object_name, object_type, status FROM user_objects')
    objects = cursor.fetchall()
    # Any collision blocks installation, even if the existing object has another type.
    names = {name for name, _ in expected}
    present = {(name, kind): status for name, kind, status in objects if name in names}
    if not present:
        return 'empty'
    if not expected.issubset(present) or any(present[key] != 'VALID' for key in expected):
        return 'partial'
    cursor.execute('SELECT COUNT(*) FROM "КЛЕТКИ"')
    cells = cursor.fetchone()[0]
    cursor.execute('SELECT COUNT(*) FROM "КАРТЫ_ШАНСА"')
    cards = cursor.fetchone()[0]
    return 'ready' if (cells, cards) == (12, 10) else 'partial'


def prepare_environment():
    if not PYTHON.exists():
        subprocess.run([sys.executable, '-m', 'venv', str(VENV)], check=True)
    requirements = ROOT / 'requirements.txt'
    digest = hashlib.sha256(requirements.read_bytes()).hexdigest()
    marker = VENV / 'requirements.sha256'
    probe = subprocess.run([str(PYTHON), '-c',
        'import sys,struct; from PyQt5 import QtWidgets; import oracledb,dotenv; '
        'assert sys.version_info[:2] == (3,12) and struct.calcsize("P") == 8'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if probe.returncode or not marker.exists() or marker.read_text() != digest:
        print('Установка зависимостей. Для первого запуска нужен интернет.', flush=True)
        subprocess.run([str(PYTHON), '-m', 'pip', 'install', '-r', str(requirements)], check=True)
        marker.write_text(digest)
    return subprocess.call([str(PYTHON), str(Path(__file__).resolve()), sys.argv[1], '--ready'], cwd=ROOT)


def run(role):
    sys.path.insert(0, str(ROOT))
    if role == 'join' and TRANSFER.exists():
        data = read_profile(TRANSFER)
    elif PROFILE.exists():
        data = read_profile(PROFILE)
    elif role == 'host':
        data = ask_profile()
    else:
        raise RuntimeError('Положите connection_for_player2.json от первого участника рядом с батниками и повторите запуск.')
    os.environ.update(data)
    # Import only after selecting credentials; ignore a legacy .env from another machine.
    from app.db import Database
    database = Database()
    try:
        with database.cursor() as cursor:
            state = schema_state(cursor)
    finally:
        database.close()
    if state == 'empty' and role == 'host':
        print('Создание таблиц, справочников и пакета MONOPOLY...', flush=True)
        from database.install import install
        install()
        database = Database()
        try:
            with database.cursor() as cursor:
                state = schema_state(cursor)
        finally:
            database.close()
    if state != 'ready':
        raise RuntimeError('Схема игры отсутствует, установлена частично или несовместима. '
            'Первый участник должен завершить установку в свободной схеме Oracle. '
            'Существующие объекты не удалены. При ошибке установки сохраните текст ошибки; '
            'DDL Oracle не откатывается автоматически.')
    save_profile(PROFILE, data)
    if role == 'host':
        save_profile(TRANSFER, data)
        print('Готово. Передайте второму участнику connection_for_player2.json из папки игры.\n'
              'Файл содержит пароль Oracle: передавайте лично, не публикуйте.', flush=True)
    print('Подключение проверено. Запускается игра...', flush=True)
    return subprocess.call([sys.executable, '-m', 'app.main'], cwd=ROOT)


def main():
    os.chdir(ROOT)
    if len(sys.argv) < 2 or sys.argv[1] not in ('host', 'join'):
        raise ValueError('Используйте один из двух батников запуска.')
    if '--ready' not in sys.argv:
        return prepare_environment()
    return run(sys.argv[1])


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (Exception, KeyboardInterrupt) as exc:
        print(f'\nЗапуск остановлен: {exc}\n'
              'Проверьте доступ к Oracle и интернету. Для смены подключения переименуйте '
              'connection.json и connection_for_player2.json и запустите первый батник снова.', file=sys.stderr)
        sys.exit(1)
