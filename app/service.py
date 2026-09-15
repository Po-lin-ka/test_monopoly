from __future__ import annotations
import oracledb
from .db import Database, DatabaseError
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
    def props(self,p): return self.db.cursor_function('monopoly.get_player_properties',[p])
    def auction(self,p): return self.db.cursor_function('monopoly.get_active_auction',[p])
    def snapshot(self,p,last_action=0,last_message=0):
        outputs=[]
        try:
            with self.db.cursor() as cursor:
                for _ in range(6):
                    outputs.append(self.db.connection.cursor())
                cursor.callproc('monopoly.get_game_snapshot',[
                    p,last_action,last_message,*outputs
                ])
                names=("state","players","cells","ownerships","actions","chat")
                result={}
                for name,ref in zip(names,outputs):
                    columns=[column[0].lower() for column in ref.description]
                    result[name]=[dict(zip(columns,row)) for row in ref]
            self.db.connection.commit()
            return result
        except oracledb.Error as exc:
            self.db.connection.rollback()
            raise DatabaseError(self.db.message(exc)) from exc
        finally:
            for ref in outputs:
                ref.close()
    def stats(self,u): return self.db.cursor_function('monopoly.get_player_stats',[u])
    def leaders(self): return self.db.cursor_function('monopoly.get_leaderboard')
    def history(self,u): return self.db.cursor_function('monopoly.get_game_history',[u])
    def ready(self,p,v): self.db.callproc('monopoly.set_ready',[p,v])
    def leave_lobby(self,p): self.db.callproc('monopoly.leave_lobby',[p])
    def delete_room(self,u,g): self.db.callproc('monopoly.abandon_waiting_game',[u,g])
    def roll(self,p):
        with self.db.cursor() as cursor:
            out=cursor.var(oracledb.NUMBER)
            result=self.db.callproc('monopoly.roll_and_move',[p,out])
            value=result[1]
            return int(value.getvalue() if hasattr(value,'getvalue') else value)
    def buy(self,p): self.db.callproc('monopoly.buy_property',[p])
    def decline_buy(self,p): self.db.callproc('monopoly.decline_purchase',[p])
    def improve(self,p): self.db.callproc('monopoly.build_house',[p])
    def decline_improve(self,p): self.db.callproc('monopoly.decline_improvement',[p])
    def sell(self,p,o): self.db.callproc('monopoly.sell_buildings',[p,o])
    def resolve_debt(self,p,mortgages,sales): self.db.callproc('monopoly.resolve_debt',[p,self.db.number_list(mortgages),self.db.number_list(sales)])
    def redeem(self,p,o): self.db.callproc('monopoly.redeem_property',[p,o])
    def bid(self,a,p,m): self.db.callproc('monopoly.make_bid',[a,p,m])
    def end(self,g): self.db.callproc('monopoly.end_turn',[g])
    def leave_game(self,p): self.db.callproc('monopoly.leave_active_game',[p])
    def disconnect(self,p): self.db.callproc('monopoly.disconnect_player',[p])
    def send(self,p,t): self.db.callproc('monopoly.send_message',[p,t])
