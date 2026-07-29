from pathlib import Path

from app.db import Database


ROOT = Path(__file__).resolve().parents[1]


def oracle_source(path):
    lines = (ROOT / path).read_text(encoding="utf-8").splitlines()
    return "\n".join(line for line in lines if line.strip() != "/" and not line.startswith("SHOW ERRORS"))


if __name__ == "__main__":
    db = Database()
    try:
        with db.cursor() as cursor:
            cursor.execute("""
                BEGIN
                    EXECUTE IMMEDIATE 'ALTER TABLE "ИГРЫ" ADD "ПОСЛЕДНЯЯ_КАРТА_ШАНСА" VARCHAR2(255 CHAR)';
                EXCEPTION
                    WHEN OTHERS THEN
                        IF SQLCODE != -1430 THEN RAISE; END IF;
                END;
            """)
            cursor.execute(oracle_source("database/07_package_spec.sql"))
            cursor.execute(oracle_source("database/08_package_body.sql"))
            cursor.execute("""
                UPDATE "КЛЕТКИ"
                   SET "БАЗОВАЯ_РЕНТА"="ЦЕНА_ПОКУПКИ",
                       "РЕНТА_1_ДОМ"=CEIL("ЦЕНА_ПОКУПКИ"*1.25),
                       "РЕНТА_2_ДОМА"=CEIL("ЦЕНА_ПОКУПКИ"*1.50),
                       "РЕНТА_ОТЕЛЬ"=CEIL("ЦЕНА_ПОКУПКИ"*1.75)
                 WHERE "ТИП"='Улица'
            """)
            cursor.execute('UPDATE "КЛЕТКИ" SET "БОНУС_СТАРТА"=50 WHERE "ТИП"=\'Старт\'')
            cursor.execute("""
                BEGIN
                    EXECUTE IMMEDIATE 'ALTER TABLE "УЧАСТНИКИ" DROP CONSTRAINT "UQ_УЧ_ИГРА_ОЧ"';
                EXCEPTION
                    WHEN OTHERS THEN
                        IF SQLCODE != -2443 THEN RAISE; END IF;
                END;
            """)
            cursor.execute("""
                BEGIN
                    EXECUTE IMMEDIATE 'DROP INDEX "UQ_УЧ_ИГРА_ОЧ"';
                EXCEPTION
                    WHEN OTHERS THEN
                        IF SQLCODE != -1418 THEN RAISE; END IF;
                END;
            """)
            cursor.execute("""
                CREATE UNIQUE INDEX "UQ_УЧ_ИГРА_ОЧ" ON "УЧАСТНИКИ"(
                    CASE WHEN "ОЧЕРЕДЬ_ХОДА" IS NOT NULL THEN "ID_ИГРЫ" END,
                    "ОЧЕРЕДЬ_ХОДА"
                )
            """)
            cursor.execute("""
                BEGIN
                    DELETE FROM "ЧАТ";
                    DELETE FROM "СТАВКИ";
                    DELETE FROM "АУКЦИОНЫ";
                    DELETE FROM "ЖУРНАЛ_ДЕЙСТВИЙ";
                    DELETE FROM "ВЛАДЕНИЯ";
                    UPDATE "ИГРЫ"
                       SET "ID_ТЕКУЩЕГО_УЧАСТНИКА"=NULL,
                           "ID_ПОБЕДИТЕЛЯ"=NULL;
                    DELETE FROM "УЧАСТНИКИ";
                    DELETE FROM "ИГРЫ";
                    DELETE FROM "ПОЛЬЗОВАТЕЛИ";
                END;
            """)
            cursor.execute("""
                SELECT object_name, status
                  FROM user_objects
                 WHERE object_name='MONOPOLY'
                   AND object_type IN ('PACKAGE','PACKAGE BODY')
                 ORDER BY object_type
            """)
            print("Пакет:", cursor.fetchall())
            cursor.execute('SELECT COUNT(*) FROM "ПОЛЬЗОВАТЕЛИ"')
            users = cursor.fetchone()[0]
            cursor.execute('SELECT COUNT(*) FROM "ИГРЫ"')
            games = cursor.fetchone()[0]
            db.connection.commit()
            print(f"После очистки: пользователей={users}, игр={games}")
    except Exception:
        db.connection.rollback()
        raise
    finally:
        db.close()
