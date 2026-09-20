from __future__ import annotations

from pathlib import Path

from app.db import Database


ROOT = Path(__file__).resolve().parent
SOURCES = (
    "02_create_tables.sql",
    "03_insert_dictionaries.sql",
    "04_insert_cells.sql",
    "05_insert_chance_cards.sql",
    "06_create_types.sql",
    "07_package_spec.sql",
    "08_package_body.sql",
)


def statements(path: Path):
    buffer = []
    block = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("SET ", "WHENEVER ", "SHOW ", "PROMPT ", "@", "--")):
            continue
        if line == "/" and not buffer:
            continue
        if not buffer:
            block = line.upper().startswith(("BEGIN", "DECLARE", "CREATE OR REPLACE PACKAGE"))
        if block:
            if line == "/":
                yield "\n".join(buffer)
                buffer = []
                block = False
            else:
                buffer.append(raw_line)
        else:
            buffer.append(raw_line)
            if line.endswith(";"):
                yield "\n".join(buffer).rstrip().removesuffix(";")
                buffer = []
    if buffer:
        yield "\n".join(buffer)


def install(sources=SOURCES, message="Схема установлена. Пакет MONOPOLY: VALID."):
    database = Database()
    try:
        with database.cursor() as cursor:
            for source in sources:
                for statement in statements(ROOT / source):
                    try:
                        cursor.execute(statement)
                    except Exception as exc:
                        raise RuntimeError(
                            f"Ошибка в {source}: {statement[:160]!r}"
                        ) from exc
            cursor.execute(
                "SELECT object_type,status FROM user_objects "
                "WHERE object_name='MONOPOLY' ORDER BY object_type"
            )
            statuses = cursor.fetchall()
            if not statuses or any(status != "VALID" for _, status in statuses):
                cursor.execute("SELECT type,line,position,text FROM user_errors WHERE name='MONOPOLY' ORDER BY type,line")
                raise RuntimeError(f"Пакет MONOPOLY невалиден: {statuses}; ошибки: {cursor.fetchall()}")
        database.connection.commit()
        print(message)
    except Exception:
        database.rollback_safely()
        raise
    finally:
        database.close()


if __name__ == "__main__":
    install()
