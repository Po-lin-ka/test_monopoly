import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication, QDialog, QMessageBox

from app import main


class FakeDatabase:
    def close(self):
        pass


class FakeService:
    def __init__(self, _db):
        self.deleted = None
        self.game_status = "ОЖИДАНИЕ"
        self.ready_call = None

    def state(self, _participant):
        return [{
            "id_игры": 7,
            "название": "Тестовая комната",
            "код_статуса_игры": self.game_status,
            "статус_игры": "Ожидание" if self.game_status == "ОЖИДАНИЕ" else "Активна",
            "состояние_хода": None,
            "код_состояния_хода": "ОЖИДАНИЕ_БРОСКА" if self.game_status == "АКТИВНА" else None,
            "id_текущего_участника": 20 if self.game_status == "АКТИВНА" else None,
            "id_хоста": 10,
        }]

    def players(self, _participant):
        return [{
            "id_участника": 20,
            "логин": "host",
            "код_статуса_участника": "АКТИВЕН" if self.game_status == "АКТИВНА" else "В_ЛОББИ",
            "готов": 0,
            "баланс": 1500,
            "позиция": 1,
            "клетка": "Старт",
            "статус": "Активен" if self.game_status == "АКТИВНА" else "В лобби",
            "очередь_хода": 1 if self.game_status == "АКТИВНА" else None,
        }]

    def list_games(self):
        return [{
            "id_игры": 7,
            "название": "Тестовая комната",
            "занято": 1,
            "макс_игроков": 4,
            "есть_пароль": 0,
        }]

    def create_game(self, user, name, maximum, password):
        self.created = (user, name, maximum, password)
        return 7

    def participant(self, user, game):
        assert (user, game) == (10, 7)
        return 20

    def board(self, _participant):
        return []

    def chat(self, _participant):
        return []

    def timer(self, _game):
        pass

    def delete_room(self, user, game):
        self.deleted = (user, game)

    def ready(self, participant, value):
        self.ready_call = (participant, value)


def make_window(monkeypatch):
    QApplication.instance() or QApplication([])
    monkeypatch.setattr(main, "Database", FakeDatabase)
    monkeypatch.setattr(main, "GameService", FakeService)
    window = main.Window()
    window.timer.stop()
    return window


def test_host_opens_lobby_and_sees_delete_button(monkeypatch):
    window = make_window(monkeypatch)
    window.user, window.part, window.game = 10, 20, 7
    window.stack.setCurrentWidget(window.lobby_page)

    window.poll(True)

    assert window.stack.currentWidget() is window.lobby_page
    assert window.lobby_players.rowCount() == 1
    assert not window.delete_button.isHidden()
    assert window.ready_button.isHidden()
    window.close()


def test_active_game_opens_game_page(monkeypatch):
    window = make_window(monkeypatch)
    window.user, window.part, window.game = 10, 20, 7
    window.s.game_status = "АКТИВНА"
    window.stack.setCurrentWidget(window.lobby_page)

    window.poll(True)

    assert window.stack.currentWidget() is window.game_page
    assert window.turn_label.text() == "ВАШ ХОД"
    assert window.balance_label.text() == "Ваш баланс: 1500 ₽"
    assert not window.roll_button.isHidden()
    assert window.roll_button.isEnabled()
    assert window.buy_button.isHidden()
    window.close()


def test_delete_room_returns_to_room_list(monkeypatch):
    window = make_window(monkeypatch)
    window.user, window.part, window.game = 10, 20, 7
    window.stack.setCurrentWidget(window.lobby_page)
    monkeypatch.setattr(QMessageBox, "question", lambda *args: QMessageBox.Yes)

    window.delete_room()

    assert window.s.deleted == (10, 7)
    assert window.part is None
    assert window.game is None
    assert window.stack.currentWidget() is window.rooms_page
    window.close()


def test_logout_returns_to_login(monkeypatch):
    window = make_window(monkeypatch)
    window.user = 10
    window.stack.setCurrentWidget(window.rooms_page)

    window.logout()

    assert window.user is None
    assert window.stack.currentWidget() is window.login_page
    window.close()


def test_room_selection_survives_refresh(monkeypatch):
    window = make_window(monkeypatch)
    window.user = 10
    window.stack.setCurrentWidget(window.rooms_page)
    window.refresh_rooms()
    window.rooms.selectRow(0)

    window.refresh_rooms()

    assert window.rooms.currentRow() == 0
    assert window.join_button.isEnabled()
    window.close()


def test_ready_button_toggles_for_two_players(monkeypatch):
    window = make_window(monkeypatch)
    window.user, window.part, window.game = 10, 20, 7
    original_players = window.s.players
    window.s.players = lambda participant: original_players(participant) + [{
        "id_участника": 21,
        "логин": "guest",
        "код_статуса_участника": "В_ЛОББИ",
        "готов": 0,
    }]
    window.stack.setCurrentWidget(window.lobby_page)
    window.poll(True)

    assert not window.ready_button.isHidden()
    assert window.ready_button.isEnabled()
    window.ready_button.click()
    assert window.s.ready_call == (20, 1)
    window.close()


def test_host_goes_directly_to_lobby_after_creation(monkeypatch):
    window = make_window(monkeypatch)
    window.user = 10
    window.stack.setCurrentWidget(window.rooms_page)
    monkeypatch.setattr(main.CreateDialog, "exec", lambda dialog: QDialog.Accepted)

    window.create()

    assert window.game == 7
    assert window.part == 20
    assert window.stack.currentWidget() is window.lobby_page
    assert window.lobby_players.rowCount() == 1
    assert window.lobby_players.item(0, 0).text().endswith("host")
    window.close()


def test_board_renders_twelve_cells_and_player_tokens():
    app = QApplication.instance() or QApplication([])
    widget = main.BoardWidget()
    widget.resize(900, 700)
    cells = []
    for position in range(1, 13):
        cell_type = "Старт" if position == 1 else "Шанс" if position == 6 else "Коммунальная" if position in (4, 9) else "Улица"
        cells.append({
            "id_клетки": position,
            "позиция": position,
            "название": f"Клетка {position}",
            "тип": cell_type,
            "цветовая_группа": f"ГРУППА_{1 if position < 7 else 2 if position < 11 else 3}" if cell_type == "Улица" else None,
            "цена_покупки": 100 if cell_type in ("Улица", "Коммунальная") else None,
            "владелец": None,
            "колво_домов": 0,
        })
    players = [{
        "id_участника": 20,
        "логин": "host",
        "позиция": 1,
        "код_статуса_участника": "АКТИВЕН",
    }]
    widget.set_state(cells, players, 20)
    widget.show()
    app.processEvents()

    image = widget.grab().toImage()
    image.save("/tmp/monopoly_board_test.png")

    assert len(widget.cell_rects) == 12
    assert not image.isNull()
    assert image.width() == 900
    assert image.height() == widget.height()
    widget.close()
