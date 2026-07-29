from __future__ import annotations

from PySide6.QtCore import QThread, Signal

from .db import Database
from .service import GameService


class SnapshotThread(QThread):
    completed = Signal(object)
    failed = Signal(str)

    def __init__(
        self,
        participant_id: int,
        last_action_id: int,
        last_message_id: int,
        known_version: int,
        include_static: bool,
        parent=None,
    ):
        super().__init__(parent)
        self.arguments = (
            participant_id,
            last_action_id,
            last_message_id,
            known_version,
            include_static,
        )

    def run(self):
        database = None
        try:
            database = Database()
            result = GameService(database).snapshot(*self.arguments)
            self.completed.emit(result)
        except Exception as exc:
            self.failed.emit(str(exc))
        finally:
            if database is not None:
                database.close()
