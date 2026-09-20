"""Обновление пакета в актуальной схеме: python -m database.upgrade."""
from .install import install

SOURCES = ("07_package_spec.sql", "08_package_body.sql")


def upgrade():
    install(SOURCES, "Пакет MONOPOLY обновлён без удаления данных: VALID.")


if __name__ == "__main__":
    upgrade()
