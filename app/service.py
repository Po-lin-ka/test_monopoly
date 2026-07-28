from __future__ import annotations
import oracledb
from .db import Database
class GameService:
    def __init__(self,db): self.db=db
    def register(self,l,p): self.db.callproc('monopoly.register_user',[l,p])
    def login(self,l,p): return int(self.db.callfunc('monopoly.authenticate_user',oracledb.NUMBER,[l,p]))
    def create_game(self,u,n,m,p):
        with self.db.cursor() as cursor:
            out=cursor.var(oracledb.NUMBER)
            result=self.db.callproc('monopoly.create_game',[u,n,m,p or None,out])
            value=result[4]
            return int(value.getvalue() if hasattr(value,'getvalue') else value)
    def list_games(self): return self.db.cursor_function('monopoly.list_waiting_games')
    def join(self,u,g,p): self.db.callproc('monopoly.join_game',[u,g,p or None])
    def participant(self,u,g):
        with self.db.cursor() as c:
            c.execute('SELECT "ID_УЧАСТНИКА" FROM "УЧАСТНИКИ" WHERE "ID_ПОЛЬЗОВАТЕЛЯ"=:u AND "ID_ИГРЫ"=:g',u=u,g=g); return int(c.fetchone()[0])
    def state(self,p): return self.db.cursor_function('monopoly.get_game_state',[p])
    def players(self,p): return self.db.cursor_function('monopoly.get_game_participants',[p])
    def board(self,p): return self.db.cursor_function('monopoly.get_board_state',[p])
    def props(self,p): return self.db.cursor_function('monopoly.get_player_properties',[p])
    def auction(self,p): return self.db.cursor_function('monopoly.get_active_auction',[p])
    def chat(self,p): return self.db.cursor_function('monopoly.get_chat',[p])
    def stats(self,u): return self.db.cursor_function('monopoly.get_player_stats',[u])
    def leaders(self): return self.db.cursor_function('monopoly.get_leaderboard')
    def history(self,u): return self.db.cursor_function('monopoly.get_game_history',[u])
    def request_start(self,g,u): self.db.callproc('monopoly.request_start',[g,u])
    def ready(self,p,v): self.db.callproc('monopoly.set_ready',[p,v])
    def start(self,g,u): self.db.callproc('monopoly.start_game',[g,u])
    def leave_lobby(self,p): self.db.callproc('monopoly.leave_lobby',[p])
    def delete_room(self,u,g): self.db.callproc('monopoly.abandon_waiting_game',[u,g])
    def roll(self,p):
        out=self.db.connection.cursor().var(oracledb.NUMBER); r=self.db.callproc('monopoly.roll_and_move',[p,out]); return int(r[1].getvalue())
    def buy(self,p,c): self.db.callproc('monopoly.buy_property',[p,c])
    def decline_buy(self,p,c): self.db.callproc('monopoly.decline_purchase',[p,c])
    def improve(self,p,c): self.db.callproc('monopoly.build_house',[p,c])
    def decline_improve(self,p,c): self.db.callproc('monopoly.decline_improvement',[p,c])
    def sell(self,p,o,n): self.db.callproc('monopoly.sell_buildings',[p,o,n])
    def mortgage(self,p,ids): self.db.callproc('monopoly.mortgage_properties',[p,self.db.number_list(ids)])
    def redeem(self,p,o): self.db.callproc('monopoly.redeem_property',[p,o])
    def bid(self,a,p,m): self.db.callproc('monopoly.make_bid',[a,p,m])
    def end(self,g): self.db.callproc('monopoly.end_turn',[g])
    def timer(self,g): self.db.callproc('monopoly.check_game_timer',[g])
    def leave_game(self,p): self.db.callproc('monopoly.leave_active_game',[p])
    def bankrupt(self,p): self.db.callproc('monopoly.declare_bankruptcy',[p,'ДОБРОВОЛЬНО'])
    def send(self,p,t): self.db.callproc('monopoly.send_message',[p,t])
