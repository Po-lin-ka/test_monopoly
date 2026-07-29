import oracledb

from app.db import Database
from app.service import GameService


if __name__ == "__main__":
    db = Database()
    service = GameService(db)
    try:
        service.register("economy_host", "test-password")
        service.register("economy_guest", "test-password")
        host = service.login("economy_host", "test-password")
        guest = service.login("economy_guest", "test-password")
        game = service.create_game(host, "Проверка экономики", 2, "")
        service.join(guest, game, "")
        participants = [service.participant(host, game), service.participant(guest, game)]
        for participant in participants:
            service.ready(participant, 1)
        with db.cursor() as cursor:
            cursor.execute(
                'UPDATE "ИГРЫ" SET "ВРЕМЯ_НАЧАЛА_ХОДА"=SYSDATE-11/86400 WHERE "ID_ИГРЫ"=:game',
                game=game,
            )
        db.connection.commit()
        service.timer(game)
        started_players = service.players(participants[0])
        assert {int(row["баланс"]) for row in started_players} == {600}
        start_cell = next(cell for cell in service.board(participants[0]) if cell["тип"] == "Старт")
        assert int(start_cell["бонус_старта"]) == 50
        current = int(service.state(participants[0])[0]["id_текущего_участника"])
        payer = next(participant for participant in participants if participant != current)
        current_name = next(
            row["логин"] for row in service.players(current)
            if int(row["id_участника"]) == current
        )

        with db.cursor() as cursor:
            cursor.execute(
                'SELECT v."ID_ВЛАДЕНИЯ",c."ЦЕНА_ПОКУПКИ" FROM "ВЛАДЕНИЯ" v '
                'JOIN "КЛЕТКИ" c ON c."ID_КЛЕТКИ"=v."ID_КЛЕТКИ" '
                'WHERE v."ID_ИГРЫ"=:game AND c."ТИП"=\'Улица\' ORDER BY c."ПОЗИЦИЯ"',
                game=game,
            )
            streets = [(int(ownership), int(price)) for ownership, price in cursor.fetchall()]
            first_ownership, first_price = streets[0]
            for level, multiplier in enumerate((1.00, 1.25, 1.50, 1.75)):
                cursor.execute(
                    'UPDATE "ВЛАДЕНИЯ" SET "КОЛВО_ДОМОВ"=:lvl_value,"ID_ВЛАДЕЛЬЦА"=:owner '
                    'WHERE "ID_ВЛАДЕНИЯ"=:ownership',
                    lvl_value=level,
                    owner=current,
                    ownership=first_ownership,
                )
                rent = int(cursor.callfunc("monopoly.calculate_rent", oracledb.NUMBER, [first_ownership, 6]))
                assert rent == int(first_price * multiplier + 0.999999)
            group_ownerships = streets[:3]
            for level, (ownership, _price) in zip((1, 3, 0), group_ownerships):
                cursor.execute(
                    'UPDATE "ВЛАДЕНИЯ" SET "ID_ВЛАДЕЛЬЦА"=:owner,"КОЛВО_ДОМОВ"=:lvl_value '
                    'WHERE "ID_ВЛАДЕНИЯ"=:ownership',
                    owner=current,
                    lvl_value=level,
                    ownership=ownership,
                )
            first_group_rent = int(
                cursor.callfunc("monopoly.calculate_rent", oracledb.NUMBER, [group_ownerships[0][0], 6])
            )
            second_group_rent = int(
                cursor.callfunc("monopoly.calculate_rent", oracledb.NUMBER, [group_ownerships[1][0], 6])
            )
            assert first_group_rent == 250
            assert second_group_rent == 386
            group_cells = [
                cell for cell in service.board(current)
                if cell.get("цветовая_группа") == "ГРУППА_1"
            ]
            assert group_cells and all(int(cell["множитель_группы"]) == 2 for cell in group_cells)
            cursor.execute(
                'UPDATE "ВЛАДЕНИЯ" SET "ID_ВЛАДЕЛЬЦА"=NULL,"КОЛВО_ДОМОВ"=0 '
                'WHERE "ID_ВЛАДЕНИЯ" IN(:second,:third)',
                second=group_ownerships[1][0],
                third=group_ownerships[2][0],
            )
            cursor.execute(
                'SELECT "ID_КЛЕТКИ" FROM "ВЛАДЕНИЯ" WHERE "ID_ВЛАДЕНИЯ"=:ownership',
                ownership=first_ownership,
            )
            first_cell = int(cursor.fetchone()[0])
            cursor.execute(
                'UPDATE "ВЛАДЕНИЯ" SET "КОЛВО_ДОМОВ"=0 WHERE "ID_ВЛАДЕНИЯ"=:ownership',
                ownership=first_ownership,
            )
            cursor.callproc("monopoly.pay_rent", [payer, first_cell, 6])
        db.connection.commit()
        rent_action = next(
            action for action in service.actions(payer)
            if action["код_действия"] == "ОПЛАТА_АРЕНДЫ"
        )
        assert rent_action["получатель"] == current_name
        assert int(rent_action["сумма"]) == first_price

        with db.cursor() as cursor:
            second_ownership, second_price = streets[1]
            cursor.execute(
                'UPDATE "ВЛАДЕНИЯ" SET "ID_ВЛАДЕЛЬЦА"=:owner,"КОЛВО_ДОМОВ"=0 '
                'WHERE "ID_ВЛАДЕНИЯ"=:ownership',
                owner=current,
                ownership=second_ownership,
            )
            cursor.execute(
                'UPDATE "УЧАСТНИКИ" SET "БАЛАНС"=1500 WHERE "ID_УЧАСТНИКА"=:owner',
                owner=current,
            )
            cursor.execute(
                'UPDATE "ИГРЫ" SET "КОД_СОСТОЯНИЯ_ХОДА"=\'ОЖИДАНИЕ_УЛУЧШЕНИЯ\','
                '"ID_ТЕКУЩЕГО_УЧАСТНИКА"=:owner WHERE "ID_ИГРЫ"=:game',
                owner=current,
                game=game,
            )
        db.connection.commit()
        with db.cursor() as cursor:
            cursor.execute(
                'SELECT "ID_КЛЕТКИ" FROM "ВЛАДЕНИЯ" WHERE "ID_ВЛАДЕНИЯ"=:ownership',
                ownership=second_ownership,
            )
            second_cell = int(cursor.fetchone()[0])
        service.improve(current, second_cell)
        with db.cursor() as cursor:
            cursor.execute(
                'SELECT v."КОЛВО_ДОМОВ",u."БАЛАНС" FROM "ВЛАДЕНИЯ" v '
                'JOIN "УЧАСТНИКИ" u ON u."ID_УЧАСТНИКА"=:owner '
                'WHERE v."ID_ВЛАДЕНИЯ"=:ownership',
                owner=current,
                ownership=second_ownership,
            )
            assert cursor.fetchone() == (1, 1500 - 138)
            cursor.execute(
                'UPDATE "ВЛАДЕНИЯ" SET "ID_ВЛАДЕЛЬЦА"=:owner,"КОЛВО_ДОМОВ"=0 '
                'WHERE "ID_ВЛАДЕНИЯ"=:ownership',
                owner=current,
                ownership=first_ownership,
            )
            cursor.execute(
                'UPDATE "ВЛАДЕНИЯ" SET "ID_ВЛАДЕЛЬЦА"=:owner,"КОЛВО_ДОМОВ"=1 '
                'WHERE "ID_ВЛАДЕНИЯ"=:ownership',
                owner=current,
                ownership=second_ownership,
            )
            cursor.execute(
                'UPDATE "УЧАСТНИКИ" SET "БАЛАНС"=-200 WHERE "ID_УЧАСТНИКА"=:owner',
                owner=current,
            )
            cursor.execute(
                'UPDATE "ИГРЫ" SET "КОД_СОСТОЯНИЯ_ХОДА"=\'ПОКРЫТИЕ_ДОЛГА\','
                '"ID_ТЕКУЩЕГО_УЧАСТНИКА"=:owner WHERE "ID_ИГРЫ"=:game',
                owner=current,
                game=game,
            )
        db.connection.commit()

        service.resolve_debt(current, [first_ownership], [second_ownership])
        with db.cursor() as cursor:
            cursor.execute(
                'SELECT "ЗАЛОЖЕНА","КОЛВО_ДОМОВ" FROM "ВЛАДЕНИЯ" '
                'WHERE "ID_ВЛАДЕНИЯ" IN(:first,:second) ORDER BY "ID_ВЛАДЕНИЯ"',
                first=first_ownership,
                second=second_ownership,
            )
            assert cursor.fetchall() == [(1, 0), (0, 0)]
            cursor.execute(
                'SELECT "БАЛАНС" FROM "УЧАСТНИКИ" WHERE "ID_УЧАСТНИКА"=:owner',
                owner=current,
            )
            expected = -200 + first_price // 2 + 69
            assert int(cursor.fetchone()[0]) == expected
        print("Экономика: улучшения без комплекта, цена нового уровня, аренда группы ×2 и долг — OK")
    finally:
        db.close()
