# Упрощённая Monopoly — Oracle PL/SQL + Python/PySide6

## Развёртывание

```bash
cd /mnt/projects/monopoly
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Установите схему (команда пересоздаёт таблицы и очищает старые игровые данные):

```bash
.venv/bin/python -m database.install
```

Запуск интерфейса:

```bash
.venv/bin/python -m app.main
```

Запускайте приложение именно как модуль из корня проекта. Команда
`python app/main.py` не подходит из-за относительных импортов пакета `app`.

Клиент раз в две секунды запускает один фоновый `get_game_snapshot`. Этот вызов
проверяет таймер в Oracle и возвращает состояние, игроков, изменившиеся владения,
новые события и сообщения. Между снимками видимый таймер уменьшается локально.
GUI-поток не ожидает сетевые запросы и не запускает второй снимок, пока не завершён
первый.
