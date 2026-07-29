import os
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication, QDialog, QPushButton

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
        assert len(window.lobby_player_cards) == 4
        assert not window.lobby_player_cards[0].findChildren(QPushButton)
        window.s.register("ui_guest_smoke", "test-password")
        guest = window.s.login("ui_guest_smoke", "test-password")
        window.s.join(guest, window.game, "")
        window.poll(True)
        assert len(window.lobby_player_cards) == 4
        ready_buttons = [
            control for control in window.lobby_player_cards[0].findChildren(QPushButton)
            if control.text() == "Я готов"
        ]
        assert len(ready_buttons) == 1 and ready_buttons[0].isEnabled()
        print(
            "Хост после создания сразу в лобби:",
            f"game={window.game}, participant={window.part}, players=2, slots={len(window.lobby_player_cards)}, ready_button=in_card",
        )
    finally:
        window.close()
