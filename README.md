# Упрощённая Monopoly — Oracle PL/SQL + Python/PySide6

## Развёртывание

```bash
cd /mnt/projects/monopoly
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Подключитесь к схеме MONOPOLY в FREEPDB1 и выполните:

```sql
@database/install.sql
```

Проверка:

```sql
@database/10_tests.sql
```

Запуск интерфейса:

```bash
.venv/bin/python -m app.main
```

Запускайте приложение именно как модуль из корня проекта. Команда
`python app/main.py` не подходит из-за относительных импортов пакета `app`.

Пакет Oracle не выполняет COMMIT/ROLLBACK. Python фиксирует успешные вызовы и откатывает ошибочные. Один QTimer Python периодически вызывает monopoly.check_game_timer; решение о тайм-ауте принимает Oracle по SYSDATE.
