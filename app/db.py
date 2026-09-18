from __future__ import annotations

from contextlib import contextmanager
from typing import Any, Iterable

import oracledb

from .config import settings


class DatabaseError(RuntimeError):
    pass


class ConnectionLost(DatabaseError):
    """Соединение или результат последней команды больше нельзя считать надёжными."""


class Database:
    def __init__(self):
        self.connection = None
        self.reconnect()

    def reconnect(self):
        self.close()
        try:
            self.connection = oracledb.connect(
                user=settings.user, password=settings.password, dsn=settings.dsn,
                tcp_connect_timeout=settings.connect_timeout_seconds, retry_count=0,
            )
            self.connection.call_timeout = settings.call_timeout_ms
        except oracledb.Error as exc:
            self.close()
            raise ConnectionLost(self.message(exc)) from exc

    @staticmethod
    def safe_close(resource):
        if resource is not None:
            try:
                resource.close()
            except oracledb.Error:
                pass

    def close(self):
        self.safe_close(self.connection)
        self.connection = None

    def rollback_safely(self):
        if self.connection is not None:
            try:
                self.connection.rollback()
            except oracledb.Error:
                pass

    def is_healthy(self):
        try:
            return self.connection is not None and self.connection.is_healthy()
        except oracledb.Error:
            return False

    def error(self, exc):
        detail = exc.args[0] if exc.args else exc
        code = getattr(detail, 'full_code', '')
        # Таймаут также требует сверки состояния: ответ на COMMIT мог потеряться.
        lost = (not self.is_healthy() or getattr(detail, 'isrecoverable', False)
                or code in {'DPY-1001', 'DPY-4011', 'DPY-4024', 'DPI-1067',
                            'DPI-1080', 'ORA-03113', 'ORA-03114', 'ORA-03135',
                            'ORA-01012', 'ORA-00028'})
        return (ConnectionLost if lost else DatabaseError)(self.message(exc))

    @contextmanager
    def cursor(self):
        cur = None
        try:
            if not self.is_healthy():
                raise ConnectionLost('Соединение с базой данных потеряно.')
            cur = self.connection.cursor()
            yield cur
        except oracledb.Error as exc:
            error = self.error(exc)
            self.rollback_safely()
            raise error from exc
        finally:
            self.safe_close(cur)

    def callproc(self, name: str, params: list[Any] | None = None):
        try:
            with self.cursor() as cur:
                result = cur.callproc(name, params or [])
            self.connection.commit()
            return result
        except oracledb.Error as exc:
            error = self.error(exc)
            self.rollback_safely()
            raise error from exc

    def callfunc(self, name: str, return_type: Any, params: list[Any] | None = None):
        with self.cursor() as cur:
            return cur.callfunc(name, return_type, params or [])

    def cursor_function(self, name: str, params: list[Any] | None = None):
        with self.cursor() as cur:
            rc = cur.callfunc(name, oracledb.DB_TYPE_CURSOR, params or [])
            try:
                cols = [x[0].lower() for x in rc.description]
                return [dict(zip(cols, row)) for row in rc]
            finally:
                self.safe_close(rc)

    def number_list(self, ids: Iterable[int]):
        with self.cursor():
            obj = self.connection.gettype('NUMBER_LIST').newobject()
            obj.extend([int(x) for x in ids])
            return obj

    @staticmethod
    def message(exc):
        err = exc.args[0] if exc.args else exc
        return getattr(err, 'message', str(exc)).strip()
