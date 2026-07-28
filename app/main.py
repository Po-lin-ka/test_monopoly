from __future__ import annotations

import math
import sys

from PySide6.QtCore import QPointF, QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import (
    QApplication, QDialog, QDialogButtonBox, QFormLayout, QFrame,
    QHBoxLayout, QHeaderView, QInputDialog, QLabel, QLineEdit, QMainWindow,
    QMessageBox, QPushButton, QSpinBox, QStackedWidget, QTableWidget,
    QTableWidgetItem, QTextEdit, QVBoxLayout, QWidget,
)

from .config import settings
from .db import Database, DatabaseError
from .service import GameService


STYLE = """
QMainWindow, QWidget { background: #f4f7fb; color: #172033; font: 14px "DejaVu Sans"; }
QFrame#card { background: white; border: 1px solid #dce4f0; border-radius: 16px; }
QLabel#title { color: #172554; font-size: 28px; font-weight: 700; }
QLabel#subtitle { color: #64748b; font-size: 14px; }
QLabel#roomTitle { color: #172554; font-size: 23px; font-weight: 700; }
QLabel#countdown { color: #c2410c; background: #ffedd5; border-radius: 10px; padding: 10px; font-size: 17px; font-weight: 700; }
QPushButton { background: #e8eef8; border: 0; border-radius: 9px; padding: 10px 16px; color: #24324a; font-weight: 600; }
QPushButton:hover { background: #dbe7f7; }
QPushButton:disabled { color: #94a3b8; background: #edf1f6; }
QPushButton#primary { background: #2563eb; color: white; }
QPushButton#primary:hover { background: #1d4ed8; }
QPushButton#success { background: #16a34a; color: white; }
QPushButton#success:hover { background: #15803d; }
QPushButton#danger { background: #dc2626; color: white; }
QPushButton#danger:hover { background: #b91c1c; }
QLineEdit, QSpinBox, QTextEdit { background: white; border: 1px solid #cbd5e1; border-radius: 8px; padding: 9px; selection-background-color: #2563eb; }
QLineEdit:focus, QSpinBox:focus, QTextEdit:focus { border: 2px solid #3b82f6; }
QTableWidget { background: white; alternate-background-color: #f8fafc; border: 1px solid #dce4f0; border-radius: 10px; gridline-color: #e5eaf2; }
QTableWidget::item { padding: 9px; }
QTableWidget::item:selected { background: #bfdbfe; color: #172554; }
QHeaderView::section { background: #e8eef8; color: #334155; border: 0; border-bottom: 1px solid #cbd5e1; padding: 10px; font-weight: 700; }
"""


def button(text, slot, kind=None):
    result = QPushButton(text)
    if kind:
        result.setObjectName(kind)
    result.clicked.connect(slot)
    return result


def setup_table(table):
    table.setAlternatingRowColors(True)
    table.setSelectionBehavior(QTableWidget.SelectRows)
    table.setSelectionMode(QTableWidget.SingleSelection)
    table.setEditTriggers(QTableWidget.NoEditTriggers)
    table.verticalHeader().setVisible(False)
    table.horizontalHeader().setStretchLastSection(True)


def fill(table, rows):
    table.clear()
    if not rows:
        table.setRowCount(0)
        table.setColumnCount(0)
        return
    columns = list(rows[0])
    table.setColumnCount(len(columns))
    table.setHorizontalHeaderLabels(columns)
    table.setRowCount(len(rows))
    for row_index, row in enumerate(rows):
        for column_index, key in enumerate(columns):
            table.setItem(row_index, column_index, QTableWidgetItem("" if row[key] is None else str(row[key])))
    table.resizeColumnsToContents()


class BoardWidget(QWidget):
    TOKEN_COLORS = ["#ef4444", "#2563eb", "#16a34a", "#a855f7"]
    CELL_COLORS = {
        "Старт": "#86efac",
        "Шанс": "#fde047",
        "Коммунальная": "#67e8f9",
    }
    GROUP_COLORS = {
        "Группа 1": "#93c5fd",
        "Группа 2": "#fdba74",
        "Группа 3": "#d8b4fe",
        "ГРУППА_1": "#93c5fd",
        "ГРУППА_2": "#fdba74",
        "ГРУППА_3": "#d8b4fe",
        "1": "#93c5fd",
        "2": "#fdba74",
        "3": "#d8b4fe",
    }

    def __init__(self, parent=None):
        super().__init__(parent)
        self.cells = []
        self.players = []
        self.current_participant = None
        self.cell_rects = []
        self.setMinimumSize(680, 600)
        self.setToolTip("Игровое поле: 12 клеток по кругу")

    def set_state(self, cells, players, current_participant=None):
        self.cells = sorted(cells, key=lambda row: int(row["позиция"]))
        self.players = players
        self.current_participant = int(current_participant) if current_participant is not None else None
        self.update()

    def cell_color(self, cell):
        if cell.get("тип") == "Улица":
            return self.GROUP_COLORS.get(str(cell.get("цветовая_группа")), "#cbd5e1")
        return self.CELL_COLORS.get(cell.get("тип"), "#e2e8f0")

    def paintEvent(self, _event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor("#eef4fb"))
        if not self.cells:
            painter.setPen(QColor("#64748b"))
            painter.setFont(QFont("DejaVu Sans", 15))
            painter.drawText(self.rect(), Qt.AlignCenter, "Игровое поле загружается…")
            return

        width, height = self.width(), self.height()
        center = QPointF(width / 2, height / 2)
        cell_width = min(154.0, max(112.0, width * 0.16))
        cell_height = min(88.0, max(66.0, height * 0.105))
        radius_x = max(190.0, width / 2 - cell_width / 2 - 22)
        radius_y = max(175.0, height / 2 - cell_height / 2 - 22)

        painter.setPen(QPen(QColor("#bfdbfe"), 18))
        painter.setBrush(Qt.NoBrush)
        painter.drawEllipse(center, radius_x * 0.78, radius_y * 0.78)

        center_rect = QRectF(center.x() - 125, center.y() - 65, 250, 130)
        painter.setPen(QPen(QColor("#bfdbfe"), 2))
        painter.setBrush(QColor("#ffffff"))
        painter.drawRoundedRect(center_rect, 22, 22)
        painter.setPen(QColor("#1e3a8a"))
        painter.setFont(QFont("DejaVu Sans", 22, QFont.Bold))
        painter.drawText(center_rect.adjusted(8, 18, -8, -44), Qt.AlignCenter, "MONOPOLY")
        painter.setPen(QColor("#64748b"))
        painter.setFont(QFont("DejaVu Sans", 10))
        painter.drawText(center_rect.adjusted(8, 68, -8, -12), Qt.AlignCenter, "Упрощённая версия • 12 клеток")

        self.cell_rects = []
        for index, cell in enumerate(self.cells):
            angle = math.radians(-90 + index * 30)
            x = center.x() + radius_x * math.cos(angle) - cell_width / 2
            y = center.y() + radius_y * math.sin(angle) - cell_height / 2
            rect = QRectF(x, y, cell_width, cell_height)
            self.cell_rects.append((int(cell["позиция"]), rect))
            painter.setPen(QPen(QColor("#334155"), 2))
            painter.setBrush(QColor(self.cell_color(cell)))
            painter.drawRoundedRect(rect, 12, 12)

            painter.setPen(QColor("#172033"))
            painter.setFont(QFont("DejaVu Sans", 8, QFont.Bold))
            name = str(cell["название"])
            if len(name) > 18:
                name = name[:17] + "…"
            painter.drawText(rect.adjusted(7, 5, -7, -28), Qt.AlignCenter | Qt.TextWordWrap, f'{cell["позиция"]}. {name}')
            details = []
            if cell.get("цена_покупки") is not None:
                details.append(f'₽{cell["цена_покупки"]}')
            if cell.get("владелец"):
                details.append(f'владелец: {cell["владелец"]}')
            if int(cell.get("колво_домов") or 0):
                level = int(cell["колво_домов"])
                details.append("отель" if level == 3 else f"домов: {level}")
            painter.setFont(QFont("DejaVu Sans", 7))
            painter.drawText(rect.adjusted(5, cell_height - 29, -5, -4), Qt.AlignCenter | Qt.TextWordWrap, " • ".join(details) or cell["тип"])

        by_position = {}
        for player_index, player in enumerate(self.players):
            if player.get("код_статуса_участника") not in ("АКТИВЕН", "В_ЛОББИ"):
                continue
            by_position.setdefault(int(player["позиция"]), []).append((player_index, player))
        for position, tokens in by_position.items():
            rect = next((item_rect for item_position, item_rect in self.cell_rects if item_position == position), None)
            if rect is None:
                continue
            for token_offset, (player_index, player) in enumerate(tokens):
                token_center = QPointF(rect.left() + 13 + token_offset * 21, rect.bottom() - 13)
                participant_id = int(player["id_участника"])
                pen_width = 4 if participant_id == self.current_participant else 2
                painter.setPen(QPen(QColor("#ffffff"), pen_width))
                painter.setBrush(QColor(self.TOKEN_COLORS[player_index % len(self.TOKEN_COLORS)]))
                painter.drawEllipse(token_center, 9, 9)
                painter.setPen(QColor("#172033"))
                painter.setFont(QFont("DejaVu Sans", 7, QFont.Bold))
                painter.drawText(QRectF(token_center.x() - 9, token_center.y() - 9, 18, 18), Qt.AlignCenter, str(player_index + 1))


class CreateDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Создание комнаты")
        self.setMinimumWidth(420)
        form = QFormLayout(self)
        self.name = QLineEdit("Новая игра")
        self.max = QSpinBox()
        self.max.setRange(2, 4)
        self.max.setValue(4)
        self.password = QLineEdit()
        self.password.setEchoMode(QLineEdit.Password)
        self.password.setPlaceholderText("Необязательно")
        form.addRow("Название", self.name)
        form.addRow("Максимум игроков", self.max)
        form.addRow("Пароль", self.password)
        controls = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        controls.accepted.connect(self.accept)
        controls.rejected.connect(self.reject)
        form.addRow(controls)


class Window(QMainWindow):
    def __init__(self):
        super().__init__()
        self.resize(1280, 820)
        self.setMinimumSize(960, 650)
        self.setWindowTitle("Monopoly Lite")
        self.setStyleSheet(STYLE)
        self.db = Database()
        self.s = GameService(self.db)
        self.user = None
        self.part = None
        self.game = None
        self.state_row = {}
        self.stack = QStackedWidget()
        self.setCentralWidget(self.stack)
        self.login_page = self.login_ui()
        self.rooms_page = self.rooms_ui()
        self.lobby_page = self.lobby_ui()
        self.game_page = self.game_ui()
        for page in (self.login_page, self.rooms_page, self.lobby_page, self.game_page):
            self.stack.addWidget(page)
        self.timer = QTimer(self)
        self.timer.setInterval(settings.poll_interval_ms)
        self.timer.timeout.connect(self.poll)
        self.timer.start()

    @staticmethod
    def page_header(title, subtitle):
        title_label = QLabel(title)
        title_label.setObjectName("title")
        subtitle_label = QLabel(subtitle)
        subtitle_label.setObjectName("subtitle")
        return title_label, subtitle_label

    def login_ui(self):
        page = QWidget()
        outer = QVBoxLayout(page)
        outer.addStretch()
        card = QFrame()
        card.setObjectName("card")
        card.setMaximumWidth(480)
        layout = QVBoxLayout(card)
        layout.setContentsMargins(42, 36, 42, 36)
        title, subtitle = self.page_header("Monopoly Lite", "Войдите или создайте новый аккаунт")
        self.le = QLineEdit()
        self.le.setPlaceholderText("Логин")
        self.pe = QLineEdit()
        self.pe.setPlaceholderText("Пароль")
        self.pe.setEchoMode(QLineEdit.Password)
        login_button = button("Войти", self.login, "primary")
        register_button = button("Зарегистрироваться", self.register)
        self.pe.returnPressed.connect(self.login)
        for widget in (title, subtitle, self.le, self.pe, login_button, register_button):
            layout.addWidget(widget)
        row = QHBoxLayout()
        row.addStretch()
        row.addWidget(card)
        row.addStretch()
        outer.addLayout(row)
        outer.addStretch()
        return page

    def rooms_ui(self):
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(28, 24, 28, 28)
        title, subtitle = self.page_header("Доступные комнаты", "Нажмите на строку, затем «Присоединиться», или дважды щёлкните по комнате")
        actions = QHBoxLayout()
        actions.addWidget(button("Обновить", self.refresh_rooms))
        actions.addWidget(button("Создать комнату", self.create, "primary"))
        self.join_button = button("Присоединиться", self.join, "success")
        self.join_button.setEnabled(False)
        actions.addWidget(self.join_button)
        actions.addStretch()
        actions.addWidget(button("Статистика", self.stats))
        actions.addWidget(button("Выйти из аккаунта", self.logout, "danger"))
        self.rooms = QTableWidget()
        setup_table(self.rooms)
        self.rooms.itemSelectionChanged.connect(lambda: self.join_button.setEnabled(self.rooms.currentRow() >= 0))
        self.rooms.cellDoubleClicked.connect(lambda *_: self.join())
        empty = QLabel("Если список пуст, создайте первую комнату.")
        empty.setObjectName("subtitle")
        layout.addWidget(title)
        layout.addWidget(subtitle)
        layout.addSpacing(12)
        layout.addLayout(actions)
        layout.addWidget(self.rooms)
        layout.addWidget(empty)
        return page

    def lobby_ui(self):
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(28, 24, 28, 28)
        self.lobby_title = QLabel("Комната")
        self.lobby_title.setObjectName("roomTitle")
        self.lobby_info = QLabel()
        self.lobby_info.setObjectName("subtitle")
        self.countdown = QLabel()
        self.countdown.setObjectName("countdown")
        self.countdown.setAlignment(Qt.AlignCenter)
        self.countdown.hide()
        self.lobby_players = QTableWidget()
        setup_table(self.lobby_players)
        controls = QHBoxLayout()
        self.ready_button = button("Я готов", self.toggle_ready, "success")
        self.ready_button.setEnabled(False)
        controls.addWidget(self.ready_button)
        controls.addStretch()
        self.delete_button = button("Удалить комнату", self.delete_room, "danger")
        controls.addWidget(self.delete_button)
        controls.addWidget(button("Выйти из комнаты", self.leave))
        controls.addWidget(button("Выйти из аккаунта", self.logout))
        hint = QLabel("Кнопка готовности появляется при двух игроках. Когда готовы все, начинается отсчёт 10 секунд — готовность можно отменить.")
        hint.setWordWrap(True)
        hint.setObjectName("subtitle")
        layout.addWidget(self.lobby_title)
        layout.addWidget(self.lobby_info)
        layout.addWidget(self.countdown)
        layout.addSpacing(8)
        layout.addWidget(QLabel("Игроки в комнате"))
        layout.addWidget(self.lobby_players)
        layout.addWidget(hint)
        layout.addLayout(controls)
        return page

    def game_ui(self):
        page = QWidget()
        main_layout = QHBoxLayout(page)
        main_layout.setContentsMargins(24, 20, 24, 24)
        left = QVBoxLayout()
        right_card = QFrame()
        right_card.setObjectName("card")
        right = QVBoxLayout(right_card)
        self.info = QLabel()
        self.info.setObjectName("roomTitle")
        self.board = BoardWidget()
        self.players = QTableWidget()
        setup_table(self.players)
        left.addWidget(self.info)
        left.addWidget(QLabel("Игровое поле"))
        left.addWidget(self.board, 2)
        left.addWidget(QLabel("Игроки"))
        left.addWidget(self.players, 1)
        actions = [
            ("Бросить кубик", self.roll, "primary"), ("Купить", self.buy, "success"),
            ("Отказаться от покупки", self.decline_buy, None), ("Улучшить", self.improve, None),
            ("Отказаться от улучшения", self.decline_improve, None), ("Завершить ход", self.end, None),
            ("Собственность", self.properties, None), ("Ставка", self.bid, None),
            ("Покинуть игру", self.leave, "danger"),
        ]
        for text, slot, kind in actions:
            right.addWidget(button(text, slot, kind))
        self.chat = QTextEdit()
        self.chat.setReadOnly(True)
        self.msg = QLineEdit()
        self.msg.setPlaceholderText("Сообщение игрокам…")
        send = button("Отправить", self.send, "primary")
        self.msg.returnPressed.connect(self.send)
        right.addWidget(QLabel("Чат"))
        right.addWidget(self.chat, 1)
        right.addWidget(self.msg)
        right.addWidget(send)
        main_layout.addLayout(left, 3)
        main_layout.addWidget(right_card, 1)
        return page

    def alert(self, text, error=False):
        (QMessageBox.critical if error else QMessageBox.information)(self, "Monopoly", text)

    def act(self, operation):
        try:
            operation()
            self.poll(True)
        except (DatabaseError, RuntimeError) as exc:
            self.alert(str(exc), True)

    def register(self):
        try:
            self.s.register(self.le.text(), self.pe.text())
            self.alert("Регистрация выполнена. Теперь войдите в аккаунт.")
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def login(self):
        try:
            self.user = self.s.login(self.le.text(), self.pe.text())
            self.stack.setCurrentWidget(self.rooms_page)
            self.refresh_rooms()
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def logout(self):
        try:
            if self.part:
                status = self.state_row.get("код_статуса_игры")
                if status in ("ОЖИДАНИЕ", "ПРОВЕРКА_ГОТОВНОСТИ"):
                    self.s.leave_lobby(self.part)
                elif status == "АКТИВНА":
                    self.s.leave_game(self.part)
        except DatabaseError as exc:
            self.alert(str(exc), True)
            return
        self.user = self.part = self.game = None
        self.state_row = {}
        self.pe.clear()
        self.rooms.clearSelection()
        self.stack.setCurrentWidget(self.login_page)
        self.le.setFocus()

    def refresh_rooms(self):
        if not self.user:
            return
        try:
            selected_game = None
            if self.rooms.currentRow() >= 0 and self.rooms.item(self.rooms.currentRow(), 0):
                selected_game = self.rooms.item(self.rooms.currentRow(), 0).text()
            games = self.s.list_games()
            rows = [{
                "№": game["id_игры"],
                "Название": game["название"],
                "Игроки": f'{game["занято"]} / {game["макс_игроков"]}',
                "Доступ": "🔒 По паролю" if int(game["есть_пароль"]) else "Открытая",
            } for game in games]
            fill(self.rooms, rows)
            self.join_button.setEnabled(False)
            if rows:
                self.rooms.horizontalHeader().setSectionResizeMode(1, QHeaderView.Stretch)
                for row in range(self.rooms.rowCount()):
                    if self.rooms.item(row, 0).text() == selected_game:
                        self.rooms.selectRow(row)
                        break
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def create(self):
        dialog = CreateDialog(self)
        if dialog.exec() != QDialog.Accepted:
            return
        try:
            game_id = self.s.create_game(self.user, dialog.name.text(), dialog.max.value(), dialog.password.text())
            self.open_room(game_id)
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def join(self):
        row = self.rooms.currentRow()
        if row < 0:
            self.alert("Сначала нажмите на строку нужной комнаты.", True)
            return
        game_id = int(self.rooms.item(row, 0).text())
        protected = "паролю" in self.rooms.item(row, 3).text().lower()
        password = ""
        if protected:
            password, accepted = QInputDialog.getText(self, "Закрытая комната", "Введите пароль:", QLineEdit.Password)
            if not accepted:
                return
        try:
            self.s.join(self.user, game_id, password)
            self.open_room(game_id)
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def open_room(self, game_id):
        """Один и тот же переход в лобби для хозяина и присоединившихся игроков."""
        self.game = int(game_id)
        self.part = self.s.participant(self.user, self.game)
        self.state_row = {}
        self.stack.setCurrentWidget(self.lobby_page)
        self.lobby_title.setText("Подключение к комнате…")
        self.lobby_info.setText("Загружаем участников")
        self.poll(True)

    def toggle_ready(self):
        ready = self.ready_button.property("ready") is True
        self.act(lambda: self.s.ready(self.part, 0 if ready else 1))

    def poll(self, force=False):
        if self.stack.currentWidget() is self.rooms_page:
            self.refresh_rooms()
            return
        if self.stack.currentWidget() not in (self.lobby_page, self.game_page) or not self.part:
            return
        try:
            rows = self.s.state(self.part)
            if not rows:
                return
            self.state_row = rows[0]
            self.game = int(self.state_row["id_игры"])
            status = self.state_row["код_статуса_игры"]
            if status in ("ОЖИДАНИЕ", "ПРОВЕРКА_ГОТОВНОСТИ"):
                self.poll_lobby(status)
                return
            if status == "АКТИВНА":
                self.stack.setCurrentWidget(self.game_page)
                self.s.timer(self.game)
            elif status in ("ЗАБРОШЕНА", "ЗАВЕРШЕНА"):
                self.return_to_rooms()
                return
            board_rows = self.s.board(self.part)
            player_rows = self.s.players(self.part)
            self.board.set_state(board_rows, player_rows, self.state_row.get("id_текущего_участника"))
            fill(self.players, player_rows)
            self.info.setText(f'{self.state_row["название"]} · {self.state_row["статус_игры"]} · {self.state_row.get("состояние_хода") or "-"}')
            try:
                self.chat.setPlainText("\n".join(f'[{x["дата_время"]}] {x["логин"]}: {x["текст"]}' for x in self.s.chat(self.part)))
            except DatabaseError:
                pass
        except DatabaseError:
            if force:
                raise

    def poll_lobby(self, status):
        self.stack.setCurrentWidget(self.lobby_page)
        all_players = self.s.players(self.part)
        me = next((row for row in all_players if int(row["id_участника"]) == self.part), None)
        if not me or me["код_статуса_участника"] != "В_ЛОББИ":
            self.return_to_rooms()
            return
        players = [row for row in all_players if row["код_статуса_участника"] == "В_ЛОББИ"]
        display = [{
            "Игрок": f'{"★ " if int(row["id_участника"]) == self.part else ""}{row["логин"]}',
            "Готовность": "✓ Готов" if int(row["готов"]) else "Ожидаем",
        } for row in players]
        fill(self.lobby_players, display)
        self.lobby_title.setText(self.state_row["название"])
        ready_count = sum(int(row["готов"]) for row in players)
        self.lobby_info.setText(f"Комната №{self.game}  •  игроков {len(players)}  •  готовы {ready_count}/{len(players)}")
        is_host = int(self.state_row["id_хоста"]) == self.user
        self.delete_button.setVisible(is_host)
        enough = len(players) >= 2
        my_ready = bool(int(me["готов"]))
        self.ready_button.setVisible(enough)
        self.ready_button.setEnabled(enough)
        self.ready_button.setProperty("ready", my_ready)
        self.ready_button.setText("Отменить готовность" if my_ready else "Я готов")
        self.ready_button.setObjectName("danger" if my_ready else "success")
        self.ready_button.style().unpolish(self.ready_button)
        self.ready_button.style().polish(self.ready_button)
        if status == "ПРОВЕРКА_ГОТОВНОСТИ":
            remaining = int(self.state_row.get("секунд_до_старта") or 0)
            self.countdown.setText(f"Все готовы! Игра начнётся через {remaining} сек. Можно отменить готовность.")
            self.countdown.show()
            self.s.timer(self.game)
        else:
            self.countdown.hide()

    def return_to_rooms(self):
        self.part = self.game = None
        self.state_row = {}
        self.stack.setCurrentWidget(self.rooms_page)
        self.refresh_rooms()

    def current_cell(self):
        me = next(row for row in self.s.players(self.part) if int(row["id_участника"]) == self.part)
        position = int(me["позиция"])
        return int(next(row["id_клетки"] for row in self.s.board(self.part) if int(row["позиция"]) == position))

    def roll(self):
        try:
            self.alert(f"Выпало: {self.s.roll(self.part)}")
            self.poll(True)
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def buy(self): self.act(lambda: self.s.buy(self.part, self.current_cell()))
    def decline_buy(self): self.act(lambda: self.s.decline_buy(self.part, self.current_cell()))
    def improve(self): self.act(lambda: self.s.improve(self.part, self.current_cell()))
    def decline_improve(self): self.act(lambda: self.s.decline_improve(self.part, self.current_cell()))
    def end(self): self.act(lambda: self.s.end(self.game))

    def properties(self):
        try:
            properties = self.s.props(self.part)
            if not properties:
                self.alert("Собственности нет")
                return
            labels = [f'{row["id_владения"]}: {row["название"]}; дома={row["колво_домов"]}; залог={row["заложена"]}' for row in properties]
            item, accepted = QInputDialog.getItem(self, "Собственность", "Объект", labels, 0, False)
            if not accepted:
                return
            ownership_id = int(item.split(":")[0])
            action, accepted = QInputDialog.getItem(self, "Действие", "Выберите", ["Заложить", "Снять залог", "Продать 1 уровень"], 0, False)
            if not accepted:
                return
            if action == "Заложить":
                self.act(lambda: self.s.mortgage(self.part, [ownership_id]))
            elif action == "Снять залог":
                self.act(lambda: self.s.redeem(self.part, ownership_id))
            else:
                self.act(lambda: self.s.sell(self.part, ownership_id, 1))
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def bid(self):
        try:
            auction = self.s.auction(self.part)
            if not auction:
                self.alert("Нет активного аукциона")
                return
            amount, accepted = QInputDialog.getInt(self, "Ставка", "Сумма, 0 — отказ", 0, 0, 100000)
            if accepted:
                self.act(lambda: self.s.bid(int(auction[0]["id_аукциона"]), self.part, amount))
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def send(self):
        text = self.msg.text().strip()
        if text:
            self.act(lambda: self.s.send(self.part, text))
            self.msg.clear()

    def leave(self):
        try:
            status = self.state_row.get("код_статуса_игры")
            if status in ("ОЖИДАНИЕ", "ПРОВЕРКА_ГОТОВНОСТИ"):
                self.s.leave_lobby(self.part)
            elif status == "АКТИВНА":
                self.s.leave_game(self.part)
            self.return_to_rooms()
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def delete_room(self):
        answer = QMessageBox.question(
            self, "Удаление комнаты", "Удалить комнату? Все участники вернутся к списку комнат.",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if answer != QMessageBox.Yes:
            return
        try:
            self.s.delete_room(self.user, self.game)
            self.return_to_rooms()
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def stats(self):
        try:
            self.alert(f"Статистика:\n{self.s.stats(self.user)}\n\nРейтинг:\n{self.s.leaders()}\n\nИстория:\n{self.s.history(self.user)}")
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def closeEvent(self, event):
        self.db.close()
        super().closeEvent(event)


def main():
    app = QApplication(sys.argv)
    try:
        window = Window()
        window.show()
        return app.exec()
    except Exception as exc:
        QMessageBox.critical(None, "Ошибка", str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
