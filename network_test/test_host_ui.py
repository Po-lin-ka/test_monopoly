import os
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication, QDialog

from app.main import CreateDialog, Window


if __name__ == "__main__":
    app = QApplication([])
    window = Window()
    window.timer.stop()
    try:
        window.s.register("ui_host_smoke", "test-password")
        window.user = window.s.login("ui_host_smoke", "test-password")
        window.stack.setCurrentWidget(window.rooms_page)
        with patch.object(CreateDialog, "exec", return_value=QDialog.Accepted):
            window.create()
        assert window.game is not None
        assert window.part is not None
        assert window.stack.currentWidget() is window.lobby_page
        assert window.lobby_players.rowCount() == 1
        assert window.ready_button.isHidden()
        window.s.register("ui_guest_smoke", "test-password")
        guest = window.s.login("ui_guest_smoke", "test-password")
        window.s.join(guest, window.game, "")
        window.poll(True)
        assert window.lobby_players.rowCount() == 2
        assert not window.ready_button.isHidden()
        assert window.ready_button.isEnabled()
        print(
            "Хост после создания сразу в лобби:",
            f"game={window.game}, participant={window.part}, players={window.lobby_players.rowCount()}, ready_button=visible",
        )
    finally:
        window.close()
