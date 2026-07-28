from __future__ import annotations
from contextlib import contextmanager
from typing import Any, Iterable
import oracledb
from .config import settings
class DatabaseError(RuntimeError): pass
class Database:
    def __init__(self): self.connection=oracledb.connect(user=settings.user,password=settings.password,dsn=settings.dsn)
    def close(self): self.connection.close()
    @contextmanager
    def cursor(self):
        cur=self.connection.cursor()
        try: yield cur
        finally: cur.close()
    def callproc(self,name:str,params:list[Any]|None=None):
        try:
            with self.cursor() as cur: result=cur.callproc(name,params or [])
            self.connection.commit(); return result
        except oracledb.Error as exc:
            self.connection.rollback(); raise DatabaseError(self.message(exc)) from exc
    def callfunc(self,name:str,return_type:Any,params:list[Any]|None=None):
        try:
            with self.cursor() as cur: return cur.callfunc(name,return_type,params or [])
        except oracledb.Error as exc: raise DatabaseError(self.message(exc)) from exc
    def cursor_function(self,name:str,params:list[Any]|None=None):
        try:
            with self.cursor() as cur:
                rc=cur.callfunc(name,oracledb.DB_TYPE_CURSOR,params or [])
                try:
                    cols=[x[0].lower() for x in rc.description]
                    return [dict(zip(cols,row)) for row in rc]
                finally: rc.close()
        except oracledb.Error as exc: raise DatabaseError(self.message(exc)) from exc
    def number_list(self,ids:Iterable[int]):
        obj=self.connection.gettype('NUMBER_LIST').newobject(); obj.extend([int(x) for x in ids]); return obj
    @staticmethod
    def message(exc):
        err=exc.args[0]; return getattr(err,'message',str(exc)).strip()
