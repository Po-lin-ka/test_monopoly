from __future__ import annotations

from PySide6.QtCore import QThread, Signal

from .db import Database
from .service import GameService


class SnapshotThread(QThread):
    completed = Signal(object)
    failed = Signal(object)

    def __init__(
        self,
        participant_id: int,
        last_action_id: int,
        last_message_id: int,
        parent=None,
    ):
        super().__init__(parent)
        self.arguments = (
            participant_id,
            last_action_id,
            last_message_id,
        )

    def run(self):
        database = None
        try:
            database = Database()
            result = GameService(database).snapshot(*self.arguments)
            self.completed.emit(result)
        except Exception as exc:
            self.failed.emit(exc)
        finally:
            if database is not None:
                database.close()


class ReconnectThread(QThread):
    """Готовит соединение и сверяет состояние до передачи его GUI."""
    def __init__(self, participant_id, last_action_id, last_message_id, parent=None):
        super().__init__(parent)
        self.arguments = (participant_id, last_action_id, last_message_id)
        self.database = None
        self.snapshot = None
        self.error = None

    def run(self):
        try:
            self.database = Database()
            service = GameService(self.database)
            if self.arguments[0] is not None:
                self.snapshot = service.snapshot(*self.arguments)
            else:
                # Проверяем не только TCP-соединение, но и доступ к схеме.
                service.list_games()
        except Exception as exc:
            self.error = exc
            if self.database is not None:
                self.database.close()
                self.database = None
