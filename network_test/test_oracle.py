from app.db import Database
import oracledb


if __name__ == "__main__":
    db = Database()
    try:
        with db.cursor() as cursor:
            cursor.execute("SELECT USER,SYSDATE FROM dual")
            print(cursor.fetchone())
            cursor.execute('SELECT COUNT(*) FROM "КЛЕТКИ"')
            print("Клеток:", cursor.fetchone()[0])
            cursor.execute('SELECT COUNT(*) FROM "КАРТЫ_ШАНСА"')
            print("Карт:", cursor.fetchone()[0])

            for login in ("smoke_host", "smoke_player_2", "smoke_player_3"):
                cursor.callproc("monopoly.register_user", [login, "test-password"])
            user_ids = []
            for login in ("smoke_host", "smoke_player_2", "smoke_player_3"):
                user_ids.append(int(cursor.callfunc("monopoly.authenticate_user", oracledb.NUMBER, [login, "test-password"])))

            game_out = cursor.var(oracledb.NUMBER)
            cursor.callproc("monopoly.create_game", [user_ids[0], "Проверка лобби", 4, None, game_out])
            game_id = int(game_out.getvalue())
            cursor.callproc("monopoly.join_game", [user_ids[1], game_id, None])
            cursor.callproc("monopoly.join_game", [user_ids[2], game_id, None])
            cursor.execute(
                'SELECT "ID_УЧАСТНИКА","ID_ПОЛЬЗОВАТЕЛЯ" FROM "УЧАСТНИКИ" WHERE "ID_ИГРЫ"=:game_id',
                game_id=game_id,
            )
            participants = {int(user): int(part) for part, user in cursor}

            for user_id in user_ids:
                cursor.callproc("monopoly.set_ready", [participants[user_id], 1])
            cursor.execute(
                'SELECT "КОД_СТАТУСА_ИГРЫ","ВРЕМЯ_НАЧАЛА_ХОДА" FROM "ИГРЫ" WHERE "ID_ИГРЫ"=:game_id',
                game_id=game_id,
            )
            status, started = cursor.fetchone()
            assert status == "ПРОВЕРКА_ГОТОВНОСТИ" and started is not None

            cursor.callproc("monopoly.set_ready", [participants[user_ids[1]], 0])
            cursor.execute(
                'SELECT "КОД_СТАТУСА_ИГРЫ","ВРЕМЯ_НАЧАЛА_ХОДА" FROM "ИГРЫ" WHERE "ID_ИГРЫ"=:game_id',
                game_id=game_id,
            )
            assert cursor.fetchone() == ("ОЖИДАНИЕ", None)

            cursor.callproc("monopoly.set_ready", [participants[user_ids[1]], 1])
            cursor.execute(
                'UPDATE "ИГРЫ" SET "ВРЕМЯ_НАЧАЛА_ХОДА"=SYSDATE-11/86400 WHERE "ID_ИГРЫ"=:game_id',
                game_id=game_id,
            )
            cursor.callproc("monopoly.check_game_timer", [game_id])
            cursor.execute(
                'SELECT "КОД_СТАТУСА_ИГРЫ" FROM "ИГРЫ" WHERE "ID_ИГРЫ"=:game_id',
                game_id=game_id,
            )
            assert cursor.fetchone()[0] == "АКТИВНА"

            cursor.callproc("monopoly.leave_active_game", [participants[user_ids[0]]])
            cursor.execute(
                'SELECT "КОД_СТАТУСА_УЧАСТНИКА" FROM "УЧАСТНИКИ" WHERE "ID_УЧАСТНИКА"=:participant',
                participant=participants[user_ids[0]],
            )
            assert cursor.fetchone()[0] == "БАНКРОТ"
            cursor.execute(
                'SELECT "КОД_СТАТУСА_ИГРЫ" FROM "ИГРЫ" WHERE "ID_ИГРЫ"=:game_id',
                game_id=game_id,
            )
            assert cursor.fetchone()[0] == "АКТИВНА"
            log_cursor = cursor.callfunc(
                "monopoly.get_action_log", oracledb.DB_TYPE_CURSOR,
                [participants[user_ids[1]]],
            )
            try:
                assert len(log_cursor.fetchall()) > 0
            finally:
                log_cursor.close()

            cursor.callproc("monopoly.disconnect_player", [participants[user_ids[1]]])
            cursor.execute(
                'SELECT "КОД_СТАТУСА_УЧАСТНИКА" FROM "УЧАСТНИКИ" WHERE "ID_УЧАСТНИКА"=:participant',
                participant=participants[user_ids[1]],
            )
            assert cursor.fetchone()[0] == "БАНКРОТ"
            print("Лобби, таймер, журнал и автоматическое банкротство при отключении: OK")

            db.connection.rollback()
    except Exception:
        db.connection.rollback()
        raise
    finally:
        db.close()
