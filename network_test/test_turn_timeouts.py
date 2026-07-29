from app.db import Database
from app.service import GameService


if __name__ == "__main__":
    db = Database()
    service = GameService(db)
    try:
        users = []
        for index in range(3):
            login = f"timeout_player_{index + 1}"
            service.register(login, "test-password")
            users.append(service.login(login, "test-password"))
        game = service.create_game(users[0], "Проверка тайм-аутов", 3, "")
        for user in users[1:]:
            service.join(user, game, "")
        participants = [service.participant(user, game) for user in users]
        for participant in participants:
            service.ready(participant, 1)
        with db.cursor() as cursor:
            cursor.execute(
                'UPDATE "ИГРЫ" SET "ВРЕМЯ_НАЧАЛА_ХОДА"=SYSDATE-11/86400 WHERE "ID_ИГРЫ"=:game',
                game=game,
            )
        db.connection.commit()
        service.timer(game)

        state = service.state(participants[0])[0]
        timed_out = int(state["id_текущего_участника"])
        with db.cursor() as cursor:
            cursor.execute(
                'UPDATE "ИГРЫ" SET "КОД_СОСТОЯНИЯ_ХОДА"=\'ЗАВЕРШЕНИЕ_ХОДА\','
                '"ВРЕМЯ_НАЧАЛА_ХОДА"=SYSDATE-121/86400 WHERE "ID_ИГРЫ"=:game',
                game=game,
            )
        db.connection.commit()
        service.timer(game)

        after_first = service.state(participants[0])[0]
        assert int(after_first["id_текущего_участника"]) != timed_out
        assert after_first["код_состояния_хода"] == "ОЖИДАНИЕ_БРОСКА"
        with db.cursor() as cursor:
            cursor.execute(
                'SELECT "БАЛАНС","КОЛ_ТАЙМАУТОВ","КОД_СТАТУСА_УЧАСТНИКА" '
                'FROM "УЧАСТНИКИ" WHERE "ID_УЧАСТНИКА"=:participant',
                participant=timed_out,
            )
            assert cursor.fetchone() == (1450, 1, "АКТИВЕН")
            cursor.execute(
                'UPDATE "ИГРЫ" SET "ID_ТЕКУЩЕГО_УЧАСТНИКА"=:participant,'
                '"КОД_СОСТОЯНИЯ_ХОДА"=\'ОЖИДАНИЕ_БРОСКА\','
                '"ВРЕМЯ_НАЧАЛА_ХОДА"=SYSDATE-121/86400 WHERE "ID_ИГРЫ"=:game',
                participant=timed_out,
                game=game,
            )
        db.connection.commit()
        service.timer(game)

        with db.cursor() as cursor:
            cursor.execute(
                'SELECT "КОЛ_ТАЙМАУТОВ","КОД_СТАТУСА_УЧАСТНИКА" '
                'FROM "УЧАСТНИКИ" WHERE "ID_УЧАСТНИКА"=:participant',
                participant=timed_out,
            )
            assert cursor.fetchone() == (2, "БАНКРОТ")
            cursor.execute(
                'SELECT COUNT(*) FROM "ЖУРНАЛ_ДЕЙСТВИЙ" '
                'WHERE "ID_ИГРЫ"=:game AND "ID_УЧАСТНИКА"=:participant '
                'AND "КОД_ДЕЙСТВИЯ"=\'ТАЙМ_АУТ\'',
                game=game,
                participant=timed_out,
            )
            assert cursor.fetchone()[0] == 2
        print("Таймер 02:00: штраф и передача хода; второй тайм-аут — банкротство: OK")
    finally:
        db.close()
