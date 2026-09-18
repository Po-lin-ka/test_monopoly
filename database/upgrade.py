"""Обновление существующей схемы без пересоздания таблиц: python -m database.upgrade."""
from .install import install

SOURCES = ("09_connection_upgrade.sql", "07_package_spec.sql", "08_package_body.sql")


def upgrade():
    install(SOURCES, "Схема обновлена без удаления данных. Пакет MONOPOLY: VALID.")


if __name__ == "__main__":
    upgrade()
