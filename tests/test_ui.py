import os
from datetime import datetime

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
        self.current_participant = 20
        self.turn_state = "ОЖИДАНИЕ_БРОСКА"
        self.left_game = None
        self.bid_call = None

    def state(self, _participant):
        return [{
            "id_игры": 7,
            "название": "Тестовая комната",
            "код_статуса_игры": self.game_status,
            "статус_игры": "Ожидание" if self.game_status == "ОЖИДАНИЕ" else "Активна",
            "состояние_хода": None,
            "код_состояния_хода": self.turn_state if self.game_status == "АКТИВНА" else None,
            "id_текущего_участника": self.current_participant if self.game_status == "АКТИВНА" else None,
            "id_победителя": 20 if self.game_status == "ЗАВЕРШЕНА" else None,
            "id_хоста": 10,
        }]

    def players(self, _participant):
        return [{
            "id_участника": 20,
            "id_пользователя": 10,
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

    def leave_game(self, participant):
        self.left_game = participant

    def auction(self, participant):
        return [{
            "id_аукциона": 55,
            "название": "Улица 1",
            "старт_цена": 50,
            "id_участника": None,
        }]

    def bid(self, auction, participant, amount):
        self.bid_call = (auction, participant, amount)

    def resolve_debt(self, participant, mortgages, sales):
        self.debt_call = (participant, mortgages, sales)


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
    assert len(window.lobby_player_cards) == 1
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


def test_turn_action_is_hidden_from_waiting_player(monkeypatch):
    window = make_window(monkeypatch)
    window.user, window.part, window.game = 10, 20, 7
    window.s.game_status = "АКТИВНА"
    window.s.current_participant = 21
    window.stack.setCurrentWidget(window.lobby_page)

    window.poll(True)

    assert window.turn_label.text() == "Ожидание следующего хода"
    assert all(action.isHidden() for action in window.action_buttons)
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
    assert len(window.lobby_player_cards) == 1
    assert any(label.text() == "host" for label in window.lobby_player_cards[0].findChildren(main.QLabel))
    window.close()


def test_player_count_uses_three_highlighted_buttons():
    QApplication.instance() or QApplication([])
    dialog = main.CreateDialog()

    assert set(dialog.count_buttons) == {2, 3, 4}
    assert dialog.player_count() == 4
    dialog.count_buttons[3].click()
    assert dialog.player_count() == 3
    assert dialog.count_buttons[3].isChecked()
    assert not dialog.count_buttons[4].isChecked()
    dialog.close()


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
            "владелец": "host" if position == 2 else None,
            "id_владельца": 20 if position == 2 else None,
            "колво_домов": 0,
            "бонус_старта": 200 if position == 1 else None,
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
    assert image.width() == widget.width()
    assert image.height() == widget.height()
    widget.close()


def test_board_animates_player_cell_by_cell():
    QApplication.instance() or QApplication([])
    widget = main.BoardWidget()
    cells = [{"позиция": position, "название": str(position), "тип": "Старт"} for position in range(1, 13)]
    player = {
        "id_участника": 20,
        "логин": "host",
        "позиция": 1,
        "код_статуса_участника": "АКТИВЕН",
    }
    widget.set_state(cells, [player], 20)
    moved = dict(player, позиция=4)
    widget.set_state(cells, [moved], 20)

    assert widget.display_positions[20] == 1
    widget.advance_animation()
    assert widget.display_positions[20] == 2
    widget.advance_animation()
    assert widget.display_positions[20] == 3
    widget.advance_animation()
    assert widget.display_positions[20] == 4
    widget.close()


def test_dice_action_is_not_formatted_as_money():
    text = main.Window.action_text({
        "дата_время": datetime(2026, 7, 29, 12, 0, 0),
        "логин": "player",
        "действие": "Бросок кубика",
        "код_действия": "БРОСОК_КУБИКА",
        "клетка": None,
        "сумма": 6,
    })

    assert "выпало 6" in text
    assert "6 ₽" not in text


def test_rent_and_timeout_actions_are_clear():
    rent = main.Window.action_text({
        "дата_время": datetime(2026, 7, 29, 12, 0, 0),
        "логин": "player",
        "действие": "Оплата аренды",
        "код_действия": "ОПЛАТА_АРЕНДЫ",
        "клетка": "Улица 1",
        "сумма": 25,
        "получатель": "owner",
    })
    timeout = main.Window.action_text({
        "дата_время": datetime(2026, 7, 29, 12, 1, 0),
        "логин": "player",
        "действие": "Тайм-аут",
        "код_действия": "ТАЙМ_АУТ",
        "клетка": None,
        "сумма": 50,
    })

    assert "player: заплатил owner аренду" in rent and "25 ₽" in rent
    assert "пропустил ход" in timeout and "штраф" in timeout


def test_rules_are_available_from_menu_and_game(monkeypatch):
    window = make_window(monkeypatch)
    room_buttons = [item.text() for item in window.rooms_page.findChildren(main.QPushButton)]
    game_buttons = [item.text() for item in window.game_page.findChildren(main.QPushButton)]

    assert "Правила" in room_buttons
    assert "Правила игры" in game_buttons
    assert "2 минуты" in main.RULES_TEXT
    window.close()


def test_mortgage_dialog_uses_checkboxes_and_calculates_total():
    QApplication.instance() or QApplication([])
    dialog = main.MortgageDialog([
        {
            "id_владения": 1,
            "название": "Улица 1",
            "цена_покупки": 100,
            "залоговая_стоимость": 50,
            "стоимость_продажи_уровня": 25,
            "колво_домов": 0,
            "заложена": 0,
            "можно_заложить": 1,
        },
        {
            "id_владения": 2,
            "название": "Улица 2",
            "цена_покупки": 110,
            "залоговая_стоимость": 55,
            "стоимость_продажи_уровня": 25,
            "колво_домов": 1,
            "заложена": 0,
            "можно_заложить": 0,
        },
    ])

    dialog.checkboxes[0].setChecked(True)
    dialog.checkboxes[1].setChecked(True)

    assert dialog.total_label.text() == "Игрок получит: 75 ₽"
    assert dialog.selected_mortgages() == [1]
    assert dialog.selected_sales() == [2]
    dialog.close()


def test_action_log_can_be_collapsed(monkeypatch):
    window = make_window(monkeypatch)
    assert not window.action_log.isHidden()

    window.toggle_action_log()

    assert window.action_log.isHidden()
    assert window.log_toggle.text().startswith("▸")
    window.close()


def test_leave_game_requires_confirmation(monkeypatch):
    window = make_window(monkeypatch)
    window.user, window.part, window.game = 10, 20, 7
    window.s.game_status = "АКТИВНА"
    window.stack.setCurrentWidget(window.lobby_page)
    window.poll(True)
    monkeypatch.setattr(QMessageBox, "question", lambda *args: QMessageBox.Cancel)

    window.confirm_leave_game()

    assert window.s.left_game is None
    assert window.part == 20
    window.close()


def test_finished_game_shows_winner_and_exit_page(monkeypatch):
    window = make_window(monkeypatch)
    window.user, window.part, window.game = 10, 20, 7
    window.s.game_status = "ЗАВЕРШЕНА"
    window.stack.setCurrentWidget(window.game_page)

    window.poll(True)

    assert window.stack.currentWidget() is window.finish_page
    assert window.winner_label.text() == "Победитель: host"
    assert "1500 ₽" in window.finish_details.text()
    window.close()


def test_auction_invitation_refusal_records_zero_bid(monkeypatch):
    window = make_window(monkeypatch)
    window.user, window.part, window.game = 10, 20, 7
    window.s.game_status = "АКТИВНА"
    window.s.current_participant = 21
    window.s.turn_state = "ПРОВЕДЕНИЕ_АУКЦИОНА"
    window.stack.setCurrentWidget(window.game_page)
    monkeypatch.setattr(QMessageBox, "question", lambda *args: QMessageBox.No)

    window.poll(True)

    assert window.s.bid_call == (55, 20, 0)
    assert 55 in window.prompted_auctions
    window.close()
