from app.db import Database, DatabaseError
from app.service import GameService


if __name__ == "__main__":
    db = Database()
    service = GameService(db)
    try:
        service.register("turn_host_smoke", "test-password")
        service.register("turn_guest_smoke", "test-password")
        host = service.login("turn_host_smoke", "test-password")
        guest = service.login("turn_guest_smoke", "test-password")
        game = service.create_game(host, "Проверка повторных ходов", 2, "")
        service.join(guest, game, "")
        host_participant = service.participant(host, game)
        guest_participant = service.participant(guest, game)
        service.ready(host_participant, 1)
        service.ready(guest_participant, 1)
        with db.cursor() as cursor:
            cursor.execute(
                'UPDATE "ИГРЫ" SET "ВРЕМЯ_НАЧАЛА_ХОДА"=SYSDATE-11/86400 WHERE "ID_ИГРЫ"=:game',
                game=game,
            )
        db.connection.commit()
        service.timer(game)

        state = service.state(host_participant)[0]
        owner = int(state["id_текущего_участника"])
        with db.cursor() as cursor:
            cursor.execute('SELECT "ID_КЛЕТКИ" FROM "КЛЕТКИ" WHERE "ПОЗИЦИЯ"=6')
            chance_cell = int(cursor.fetchone()[0])
            cursor.execute(
                'UPDATE "УЧАСТНИКИ" SET "ID_ПОЗИЦИИ"=:cell WHERE "ID_УЧАСТНИКА"=:owner',
                cell=chance_cell, owner=owner,
            )
        db.connection.commit()
        db.callproc("monopoly.apply_chance", [owner, 1])
        assert service.state(owner)[0]["последняя_карта_шанса"]

        with db.cursor() as cursor:
            cursor.execute(
                'SELECT "ID_ВЛАДЕНИЯ" FROM "ВЛАДЕНИЯ" v JOIN "КЛЕТКИ" c ON c."ID_КЛЕТКИ"=v."ID_КЛЕТКИ" '
                'WHERE v."ID_ИГРЫ"=:game AND c."ПОЗИЦИЯ"=2',
                game=game,
            )
            ownership = int(cursor.fetchone()[0])
            cursor.execute(
                'UPDATE "ВЛАДЕНИЯ" SET "ID_ВЛАДЕЛЬЦА"=:owner WHERE "ID_ВЛАДЕНИЯ"=:ownership',
                owner=owner, ownership=ownership,
            )
            cursor.execute(
                'UPDATE "УЧАСТНИКИ" SET "БАЛАНС"=-10 WHERE "ID_УЧАСТНИКА"=:owner',
                owner=owner,
            )
            cursor.execute(
                'UPDATE "ИГРЫ" SET "КОД_СОСТОЯНИЯ_ХОДА"=\'ПОКРЫТИЕ_ДОЛГА\' WHERE "ID_ИГРЫ"=:game',
                game=game,
            )
        db.connection.commit()
        service.mortgage(owner, [ownership])
        balance = next(row["баланс"] for row in service.players(owner) if int(row["id_участника"]) == owner)
        assert int(balance) == 40

        with db.cursor() as cursor:
            cursor.execute(
                'UPDATE "УЧАСТНИКИ" SET "БАЛАНС"=1500 WHERE "ID_УЧАСТНИКА"=:owner',
                owner=owner,
            )
            cursor.execute(
                'UPDATE "ИГРЫ" SET "ID_ТЕКУЩЕГО_УЧАСТНИКА"=:owner,'
                '"КОД_СОСТОЯНИЯ_ХОДА"=\'ОЖИДАНИЕ_БРОСКА\' WHERE "ID_ИГРЫ"=:game',
                owner=owner, game=game,
            )
        db.connection.commit()
        service.redeem(owner, ownership)
        balance = next(row["баланс"] for row in service.players(owner) if int(row["id_участника"]) == owner)
        assert int(balance) == 1390
        try:
            service.mortgage(owner, [ownership])
            raise AssertionError("Добровольный залог не был запрещён")
        except DatabaseError:
            pass

        completed_turns = 0
        rolls = []
        while completed_turns < 8:
            state = service.state(host_participant)[0]
            current = int(state["id_текущего_участника"])
            turn_state = state["код_состояния_хода"]
            if turn_state == "ОЖИДАНИЕ_БРОСКА":
                rolls.append(service.roll(current))
            elif turn_state == "ОЖИДАНИЕ_ПОКУПКИ":
                me = next(row for row in service.players(current) if int(row["id_участника"]) == current)
                cell = next(row for row in service.board(current) if int(row["позиция"]) == int(me["позиция"]))
                service.buy(current, int(cell["id_клетки"]))
            elif turn_state == "ОЖИДАНИЕ_УЛУЧШЕНИЯ":
                me = next(row for row in service.players(current) if int(row["id_участника"]) == current)
                cell = next(row for row in service.board(current) if int(row["позиция"]) == int(me["позиция"]))
                service.decline_improve(current, int(cell["id_клетки"]))
            elif turn_state == "ЗАВЕРШЕНИЕ_ХОДА":
                service.end(game)
                completed_turns += 1
            else:
                raise AssertionError(f"Неожиданное состояние хода: {turn_state}")
        assert len(rolls) == 8
        assert all(1 <= dice <= 6 for dice in rolls)
        print(f"Повторные ходы и залог/выкуп: OK, завершено={completed_turns}, броски={rolls}")
    finally:
        db.close()
