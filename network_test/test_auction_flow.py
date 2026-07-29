from app.db import Database
from app.service import GameService


if __name__ == "__main__":
    db = Database()
    service = GameService(db)
    try:
        users = []
        for index in range(3):
            login = f"auction_player_{index + 1}"
            service.register(login, "test-password")
            users.append(service.login(login, "test-password"))
        game = service.create_game(users[0], "Проверка аукциона", 3, "")
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
        initiator = int(state["id_текущего_участника"])
        others = [participant for participant in participants if participant != initiator]
        board = service.board(initiator)
        first_cell = int(next(row["id_клетки"] for row in board if int(row["позиция"]) == 2))
        with db.cursor() as cursor:
            cursor.execute(
                'UPDATE "ИГРЫ" SET "КОД_СОСТОЯНИЯ_ХОДА"=\'ОЖИДАНИЕ_ПОКУПКИ\' WHERE "ID_ИГРЫ"=:game',
                game=game,
            )
        db.connection.commit()
        service.decline_buy(initiator, first_cell)
        auction = service.auction(others[0])[0]
        auction_id = int(auction["id_аукциона"])
        service.bid(auction_id, others[0], 0)
        assert service.auction(others[1])
        service.bid(auction_id, others[1], 0)
        assert not service.auction(others[0])
        after_refusal = service.state(others[0])[0]
        assert after_refusal["код_состояния_хода"] == "ОЖИДАНИЕ_БРОСКА"
        assert int(after_refusal["id_текущего_участника"]) != initiator

        second_initiator = int(after_refusal["id_текущего_участника"])
        second_others = [participant for participant in participants if participant != second_initiator]
        second_cell = int(next(row["id_клетки"] for row in board if int(row["позиция"]) == 3))
        with db.cursor() as cursor:
            cursor.execute(
                'UPDATE "ИГРЫ" SET "КОД_СОСТОЯНИЯ_ХОДА"=\'ОЖИДАНИЕ_ПОКУПКИ\' WHERE "ID_ИГРЫ"=:game',
                game=game,
            )
        db.connection.commit()
        service.decline_buy(second_initiator, second_cell)
        auction = service.auction(second_others[0])[0]
        second_auction_id = int(auction["id_аукциона"])
        start_price = int(auction["старт_цена"])
        service.bid(second_auction_id, second_others[0], start_price)
        service.bid(second_auction_id, second_others[1], 0)
        with db.cursor() as cursor:
            cursor.execute(
                'UPDATE "АУКЦИОНЫ" SET "ДАТА_НАЧАЛА"=SYSDATE-31/86400 WHERE "ID_АУКЦИОНА"=:auction',
                auction=second_auction_id,
            )
        db.connection.commit()
        service.timer(game)
        with db.cursor() as cursor:
            cursor.execute(
                'SELECT "ID_ВЛАДЕЛЬЦА" FROM "ВЛАДЕНИЯ" WHERE "ID_ИГРЫ"=:game AND "ID_КЛЕТКИ"=:cell',
                game=game,
                cell=second_cell,
            )
            assert int(cursor.fetchone()[0]) == second_others[0]
        final_state = service.state(second_others[0])[0]
        assert final_state["код_состояния_хода"] == "ОЖИДАНИЕ_БРОСКА"
        assert int(final_state["id_текущего_участника"]) != second_initiator
        print("Аукцион: приглашения, общий отказ, победитель и автоматический следующий ход — OK")
    finally:
        db.close()
