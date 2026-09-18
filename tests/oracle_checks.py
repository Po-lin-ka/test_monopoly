"""Интеграционные проверки присутствия; все игровые данные откатываются.
Запуск из корня: .venv/bin/python tests/oracle_checks.py
Сначала обновить схему: python -m database.upgrade.
"""
import sys
from pathlib import Path
from uuid import uuid4
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import oracledb
from app.db import Database


def main():
    database = Database()
    cursor = database.connection.cursor()

    def proc(name, *args):
        return cursor.callproc('monopoly.' + name, list(args))

    def scalar(sql, **params):
        cursor.execute(sql, params)
        return cursor.fetchone()[0]

    def snapshot(participant):
        refs = [database.connection.cursor() for _ in range(6)]
        try:
            proc('get_game_snapshot', participant, 0, 0, *refs)
            return [ref.fetchall() for ref in refs]
        finally:
            for ref in refs:
                ref.close()

    def create_game(count=2):
        users = []
        for _ in range(count):
            login = 'presence_' + uuid4().hex[:12]
            proc('register_user', login, 'test123')
            users.append(int(cursor.callfunc('monopoly.authenticate_user', oracledb.NUMBER, [login, 'test123'])))
        out = cursor.var(oracledb.NUMBER)
        proc('create_game', users[0], 'presence regression', count, None, out)
        game = int(out.getvalue())
        for user in users[1:]:
            proc('join_game', user, game, None)
        cursor.execute('SELECT "ID_УЧАСТНИКА" FROM "УЧАСТНИКИ" WHERE "ID_ИГРЫ"=:g ORDER BY "ID_УЧАСТНИКА"', g=game)
        players = [int(row[0]) for row in cursor.fetchall()]
        for player in players:
            proc('set_ready', player, 1)
        cursor.execute('UPDATE "УЧАСТНИКИ" SET "ПОСЛЕДНЯЯ_СВЯЗЬ"=SYSDATE-1 WHERE "ID_ИГРЫ"=:g', g=game)
        cursor.execute('UPDATE "ИГРЫ" SET "ВРЕМЯ_НАЧАЛА_ХОДА"=SYSDATE-1 WHERE "ID_ИГРЫ"=:g', g=game)
        snapshot(players[0])
        assert scalar('SELECT COUNT(*) FROM "УЧАСТНИКИ" WHERE "ID_ИГРЫ"=:g AND "ПОСЛЕДНЯЯ_СВЯЗЬ">SYSDATE-5/86400', g=game) == count
        return game, players

    def age(player, seconds):
        cursor.execute('UPDATE "УЧАСТНИКИ" SET "ПОСЛЕДНЯЯ_СВЯЗЬ"=SYSDATE-:seconds/86400 WHERE "ID_УЧАСТНИКА"=:p', seconds=seconds, p=player)

    def status(player):
        return scalar('SELECT "КОД_СТАТУСА_УЧАСТНИКА" FROM "УЧАСТНИКИ" WHERE "ID_УЧАСТНИКА"=:p', p=player)

    def winner(game):
        return scalar('SELECT "ID_ПОБЕДИТЕЛЯ" FROM "ИГРЫ" WHERE "ID_ИГРЫ"=:g', g=game)

    try:
        game, players = create_game()
        age(players[1], 30)
        snapshot(players[0])
        assert status(players[1]) == 'АКТИВЕН'
        assert scalar('SELECT (SYSDATE-"ПОСЛЕДНЯЯ_СВЯЗЬ")*86400 FROM "УЧАСТНИКИ" WHERE "ID_УЧАСТНИКА"=:p', p=players[1]) >= 30
        snapshot(players[1])
        assert status(players[1]) == 'АКТИВЕН'
        assert scalar('SELECT (SYSDATE-"ПОСЛЕДНЯЯ_СВЯЗЬ")*86400 FROM "УЧАСТНИКИ" WHERE "ID_УЧАСТНИКА"=:p', p=players[1]) < 5
        print('PASS: start resets grace period; own heartbeat only; short outage recovers')

        age(players[1], 61)
        snapshot(players[0])
        assert status(players[1]) == 'ПОКИНУЛ'
        assert winner(game) == players[0]
        snapshot(players[1])
        assert status(players[1]) == 'ПОКИНУЛ'
        assert winner(game) == players[0]
        assert scalar('SELECT COUNT(*) FROM "ЖУРНАЛ_ДЕЙСТВИЙ" WHERE "ID_УЧАСТНИКА"=:p AND "КОД_ДЕЙСТВИЯ"=\'ВЫХОД_УЧАСТНИКА\'', p=players[1]) == 1
        print('PASS: lost client loses after 60s; opponent wins; no resurrection or duplicate exit')

        game, players = create_game()
        proc('disconnect_player', players[1])
        assert winner(game) == players[0]
        print('PASS: normal exit awards immediate victory')

        game, players = create_game(3)
        current = int(scalar('SELECT "ID_ТЕКУЩЕГО_УЧАСТНИКА" FROM "ИГРЫ" WHERE "ID_ИГРЫ"=:g', g=game))
        observer = next(p for p in players if p != current)
        age(current, 61)
        snapshot(observer)
        assert status(current) == 'ПОКИНУЛ'
        assert winner(game) is None
        assert scalar('SELECT "ID_ТЕКУЩЕГО_УЧАСТНИКА" FROM "ИГРЫ" WHERE "ID_ИГРЫ"=:g', g=game) != current
        print('PASS: three players continue with next turn after current player disconnects')

        game, players = create_game(3)
        for player in players:
            age(player, 61)
        snapshot(players[0])
        assert winner(game) is None
        assert scalar('SELECT "КОД_СТАТУСА_ИГРЫ" FROM "ИГРЫ" WHERE "ID_ИГРЫ"=:g', g=game) == 'ЗАВЕРШЕНА'
        assert all(status(player) == 'ПОКИНУЛ' for player in players)
        print('PASS: all disconnected ends without an arbitrary winner')

        game, players = create_game(4)
        for player in players[1:]:
            age(player, 61)
        snapshot(players[0])
        assert winner(game) == players[0]
        print('PASS: several expired players are excluded in one snapshot')

        game, players = create_game()
        current = int(scalar('SELECT "ID_ТЕКУЩЕГО_УЧАСТНИКА" FROM "ИГРЫ" WHERE "ID_ИГРЫ"=:g', g=game))
        other = next(p for p in players if p != current)
        cell = scalar('SELECT MIN("ID_КЛЕТКИ") FROM "КЛЕТКИ" WHERE "ЦЕНА_ПОКУПКИ" IS NOT NULL')
        cursor.execute('UPDATE "УЧАСТНИКИ" SET "ID_ПОЗИЦИИ"=:cell WHERE "ID_УЧАСТНИКА"=:p', cell=cell, p=current)
        cursor.execute('UPDATE "ИГРЫ" SET "КОД_СОСТОЯНИЯ_ХОДА"=\'ОЖИДАНИЕ_ПОКУПКИ\' WHERE "ID_ИГРЫ"=:g', g=game)
        proc('decline_purchase', current)
        age(other, 61)
        snapshot(current)
        assert winner(game) == current
        assert scalar('SELECT COUNT(*) FROM "АУКЦИОНЫ" WHERE "ID_ИГРЫ"=:g AND "КОД_СТАТУСА_АУКЦИОНА"=\'АКТИВЕН\'', g=game) == 0
        print('PASS: disconnect during auction finishes game and closes auction')
    finally:
        database.rollback_safely()
        cursor.close()
        database.close()


if __name__ == '__main__':
    main()
