from app.db import Database
from app.service import GameService


if __name__ == "__main__":
    db = Database()
    service = GameService(db)
    try:
        service.register("insolvency_host", "test-password")
        service.register("insolvency_guest", "test-password")
        host = service.login("insolvency_host", "test-password")
        guest = service.login("insolvency_guest", "test-password")
        game = service.create_game(host, "Проверка банкротства", 2, "")
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

        state = service.state(participants[0])[0]
        loser = int(state["id_текущего_участника"])
        winner = next(participant for participant in participants if participant != loser)
        board = service.board(loser)
        winner_cell = next(cell for cell in board if cell["тип"] == "Улица")
        pledged_cell = next(
            cell for cell in board
            if cell["тип"] == "Улица" and int(cell["id_клетки"]) != int(winner_cell["id_клетки"])
        )
        with db.cursor() as cursor:
            cursor.execute(
                'UPDATE "ВЛАДЕНИЯ" SET "ID_ВЛАДЕЛЬЦА"=:winner,"ЗАЛОЖЕНА"=0 '
                'WHERE "ID_ИГРЫ"=:game AND "ID_КЛЕТКИ"=:cell',
                winner=winner,
                game=game,
                cell=winner_cell["id_клетки"],
            )
            cursor.execute(
                'UPDATE "ВЛАДЕНИЯ" SET "ID_ВЛАДЕЛЬЦА"=:loser,"ЗАЛОЖЕНА"=1 '
                'WHERE "ID_ИГРЫ"=:game AND "ID_КЛЕТКИ"=:cell',
                loser=loser,
                game=game,
                cell=pledged_cell["id_клетки"],
            )
            cursor.execute(
                'UPDATE "УЧАСТНИКИ" SET "БАЛАНС"=0 WHERE "ID_УЧАСТНИКА"=:loser',
                loser=loser,
            )
            cursor.callproc("monopoly.pay_rent", [loser, winner_cell["id_клетки"], 1])
        db.connection.commit()

        final_state = service.state(winner)[0]
        assert final_state["код_статуса_игры"] == "ЗАВЕРШЕНА"
        assert int(final_state["id_победителя"]) == winner
        final_players = service.players(winner)
        loser_row = next(row for row in final_players if int(row["id_участника"]) == loser)
        assert loser_row["код_статуса_участника"] == "БАНКРОТ"
        print("Непокрываемый долг: автоматическое банкротство и победа второго игрока — OK")
    finally:
        db.close()
