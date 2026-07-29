from __future__ import annotations

import math
import re
import sys

from PySide6.QtCore import QPointF, QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QFont, QPainter, QPen, QPolygonF
from PySide6.QtWidgets import (
    QApplication, QButtonGroup, QCheckBox, QDialog, QDialogButtonBox, QFormLayout, QFrame,
    QGridLayout, QHBoxLayout, QHeaderView, QInputDialog, QLabel, QLineEdit, QMainWindow,
    QMessageBox, QPushButton, QSpinBox, QStackedWidget, QTabWidget, QTableWidget,
    QTableWidgetItem, QTextEdit, QVBoxLayout, QWidget,
)

from .config import settings
from .db import Database, DatabaseError
from .service import GameService
from .snapshot import SnapshotThread

APP_VERSION = "2026.07.29-13"

RULES_TEXT = """
Цель игры
Остаться единственным небанкротом. Перед началом общий банк 1200 ₽ делится поровну
между всеми участниками: 600 ₽ для двух, 400 ₽ для трёх или 300 ₽ для четырёх.

Комната и старт
При двух и более участниках нажмите «Я готов» в своей карточке. Нажатие
«Отменить готовность» возвращает статус ожидания. Когда готовы все, запускается
10-секундный отсчёт; за это время готовность ещё можно отменить.

Ход игрока
На ход даётся 2 минуты. После броска стрелка проходит выпавшее число клеток.
Текущий игрок указан над центром поля, число кубика — внутри. После доступного
действия завершите ход.

Клетки
• Старт — при полном круге начисляется 100 ₽.
• Свободная собственность — её можно купить или отказаться и открыть аукцион.
• Чужая собственность — аренда автоматически переходит владельцу; платёж показан
  в центре и журнале.
• Депо и МЦД — особая собственность. Аренда равна результату броска ×25 ₽,
  а при владении обеими такими клетками — результату броска ×50 ₽.
• Своя улица — при повторном попадании можно последовательно купить первый дом,
  второй дом, затем отель. Владеть всей группой для строительства не требуется.
• Шанс — случайная премия +50/+100 ₽, штраф −50/−100 ₽ или перемещение;
  денежный эффект не превышает бонус Старта, карта показана в центре.

Аренда, группы и улучшения
Базовая аренда улицы равна цене покупки. С первым домом она составляет 125%,
со вторым — 150%, с отелем — 175% цены улицы. Покупка каждого улучшения —
первого дома, второго дома или отеля — стоит 25% первоначальной цены улицы.
Если один игрок владеет всеми незаложенными улицами цветовой группы, аренда каждой
из них удваивается независимо от разных уровней улучшений.
Зелёная группа: Домодедовская, Каширская, Павелецкая. Оранжевая: ВДНХ,
Сухаревская, Третьяковская. Коричневая: Добрынинская, Октябрьская.

Аукцион
Игроки, кроме отказавшегося от покупки, выбирают участие. Ставка должна быть не
меньше половины цены клетки и не больше баланса. Аукцион длится не более 30 секунд
и завершается раньше, если ответили все. Побеждает максимальная ставка; при общем
отказе клетка остаётся банку, после чего ход переходит следующему игроку.

Долг и залог
При отрицательном балансе окно покрытия долга открывается автоматически. Залог
приносит половину цены объекта.
Объект с постройками сначала требует их продажи. В окне долга можно выбрать
несколько действий и увидеть общую сумму. Выкуп стоит 110% первоначальной цены.
Если баланс остаётся отрицательным и больше нечего продать или заложить, игрок
немедленно становится банкротом; последний активный игрок побеждает.

Тайм-аут и завершение
Первый пропущенный ход автоматически завершается со штрафом 50 ₽. За второй
пропущенный ход игрок объявляется банкротом. Добровольный выход из активной игры
тоже означает банкротство. Последний активный игрок становится победителем.
""".strip()

STYLE = """
QMainWindow, QWidget { background: #f4f7fb; color: #172033; font: 14px "DejaVu Sans"; }
QLabel { background: transparent; }
QFrame#card { background: white; border: 1px solid #dce4f0; border-radius: 16px; }
QLabel#title { color: #172554; font-size: 28px; font-weight: 700; }
QLabel#subtitle { color: #64748b; font-size: 14px; }
QLabel#roomTitle { color: #172554; font-size: 23px; font-weight: 700; }
QLabel#countdown { color: #c2410c; background: #ffedd5; border-radius: 10px; padding: 10px; font-size: 17px; font-weight: 700; }
QLabel#yourTurn { color: white; background: #16a34a; border-radius: 12px; padding: 12px; font-size: 20px; font-weight: 800; }
QLabel#waitingTurn { color: #1e3a8a; background: #dbeafe; border-radius: 12px; padding: 12px; font-size: 18px; font-weight: 700; }
QLabel#balance { color: #166534; background: #dcfce7; border-radius: 10px; padding: 10px; font-size: 17px; font-weight: 700; }
QPushButton { background: #e8eef8; border: 0; border-radius: 9px; padding: 10px 16px; color: #24324a; font-weight: 600; }
QPushButton:hover { background: #dbe7f7; }
QPushButton:disabled { color: #94a3b8; background: #edf1f6; }
QPushButton#primary { background: #2563eb; color: white; }
QPushButton#primary:hover { background: #1d4ed8; }
QPushButton#success { background: #16a34a; color: white; }
QPushButton#success:hover { background: #15803d; }
QPushButton#danger { background: #dc2626; color: white; }
QPushButton#danger:hover { background: #b91c1c; }
QPushButton#countChoice { background: white; border: 2px solid #cbd5e1; font-size: 20px; padding: 12px 24px; }
QPushButton#countChoice:checked { background: #2563eb; border-color: #1d4ed8; color: white; }
QFrame#playerCard { background: white; border: 2px solid #dbe3ee; border-radius: 14px; }
QFrame#readyCard { background: #f0fdf4; border: 2px solid #22c55e; border-radius: 14px; }
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
    CELL_STRIPE_COLORS = {
        "Старт": "#a7c98f",
        "Шанс": "#e7c85b",
        "Коммунальная": "#8ab9ca",
    }
    GROUP_COLORS = {
        "Группа 1": "#72ad82",
        "Группа 2": "#dda25f",
        "Группа 3": "#bda38f",
        "ГРУППА_1": "#72ad82",
        "ГРУППА_2": "#dda25f",
        "ГРУППА_3": "#bda38f",
        "1": "#72ad82",
        "2": "#dda25f",
        "3": "#bda38f",
    }

    def __init__(self, parent=None):
        super().__init__(parent)
        self.cells = []
        self.players = []
        self.current_participant = None
        self.last_dice = None
        self.chance_text = None
        self.current_player_name = None
        self.center_event = None
        self.display_positions = {}
        self.animation_targets = {}
        self.animation_timer = QTimer(self)
        self.animation_timer.setInterval(550)
        self.animation_timer.timeout.connect(self.advance_animation)
        self.repaint_pending = False
        self.cell_rects = []
        self.setMinimumSize(1400, 900)
        self.setToolTip("Игровое поле: 12 клеток по кругу")

    def set_state(self, cells, players, current_participant=None, last_dice=None, chance_text=None):
        self.cells = sorted(cells, key=lambda row: int(row["позиция"]))
        self.players = players
        self.current_participant = int(current_participant) if current_participant is not None else None
        new_dice = int(last_dice) if last_dice is not None else None
        if self.last_dice is not None and new_dice != self.last_dice:
            self.center_event = None
        self.last_dice = new_dice
        self.chance_text = chance_text
        current = next(
            (row for row in players if current_participant is not None
             and int(row["id_участника"]) == int(current_participant)),
            None,
        )
        self.current_player_name = current.get("логин") if current else None
        active_ids = set()
        for player in players:
            participant_id = int(player["id_участника"])
            active_ids.add(participant_id)
            target = int(player["позиция"])
            if participant_id not in self.display_positions:
                self.display_positions[participant_id] = target
            elif self.display_positions[participant_id] != target:
                self.animation_targets[participant_id] = target
        self.display_positions = {
            participant_id: position for participant_id, position in self.display_positions.items()
            if participant_id in active_ids
        }
        if self.animation_targets and not self.animation_timer.isActive():
            self.animation_timer.start()
        self.schedule_repaint()

    def set_center_event(self, text):
        self.center_event = text
        self.schedule_repaint()

    def schedule_repaint(self):
        if self.repaint_pending:
            return
        self.repaint_pending = True
        QTimer.singleShot(0, self.flush_repaint)

    def flush_repaint(self):
        self.repaint_pending = False
        self.update()

    def advance_animation(self):
        finished = []
        for participant_id, target in self.animation_targets.items():
            current = self.display_positions.get(participant_id, target)
            if current == target:
                finished.append(participant_id)
                continue
            self.display_positions[participant_id] = current % 12 + 1
            if self.display_positions[participant_id] == target:
                finished.append(participant_id)
        for participant_id in finished:
            self.animation_targets.pop(participant_id, None)
        if not self.animation_targets:
            self.animation_timer.stop()
        self.schedule_repaint()

    def cell_color(self, cell):
        return "#e5e7eb" if int(cell.get("заложена") or 0) else "#ffffff"

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
        cell_width = min(205.0, max(170.0, width * 0.17))
        cell_height = min(148.0, max(124.0, height * 0.15))
        radius_x = max(300.0, width / 2 - cell_width / 2 - 42)
        radius_y = max(265.0, height / 2 - cell_height / 2 - 42)

        painter.setPen(QPen(QColor("#bfdbfe"), 18))
        painter.setBrush(Qt.NoBrush)
        painter.drawEllipse(center, radius_x * 0.78, radius_y * 0.78)

        center_rect = QRectF(center.x() - 165, center.y() - 105, 330, 210)
        painter.setPen(QPen(QColor("#bfdbfe"), 2))
        painter.setBrush(QColor("#ffffff"))
        painter.drawRoundedRect(center_rect, 22, 22)
        painter.setPen(QColor("#1e3a8a"))
        painter.setFont(QFont("DejaVu Sans", 13, QFont.Bold))
        turn_text = f"ХОДИТ: {self.current_player_name}" if self.current_player_name else "ОЖИДАНИЕ ХОДА"
        painter.drawText(
            QRectF(center_rect.left(), center_rect.top() - 42, center_rect.width(), 32),
            Qt.AlignCenter,
            turn_text,
        )
        painter.setFont(QFont("DejaVu Sans", 52, QFont.Bold))
        painter.drawText(center_rect.adjusted(8, 4, -8, -105), Qt.AlignCenter, str(self.last_dice or "—"))
        painter.setPen(QPen(QColor("#dbeafe"), 2))
        painter.drawLine(
            QPointF(center_rect.left() + 24, center_rect.center().y()),
            QPointF(center_rect.right() - 24, center_rect.center().y()),
        )
        event_text = (
            f'Карта «Шанс»\n{self.chance_text}'
            if self.chance_text
            else self.center_event or "Ожидание первого действия"
        )
        painter.setPen(QColor("#0f172a"))
        painter.setFont(QFont("DejaVu Sans", 12, QFont.Bold))
        painter.drawText(
            center_rect.adjusted(20, 112, -20, -14),
            Qt.AlignCenter | Qt.TextWordWrap,
            str(event_text),
        )

        self.cell_rects = []
        for index, cell in enumerate(self.cells):
            angle = math.radians(-90 + index * 30)
            x = center.x() + radius_x * math.cos(angle) - cell_width / 2
            y = center.y() + radius_y * math.sin(angle) - cell_height / 2
            rect = QRectF(x, y, cell_width, cell_height)
            self.cell_rects.append((int(cell["позиция"]), rect))
            owner_id = cell.get("id_владельца")
            owner_index = next(
                (player_index for player_index, player in enumerate(self.players)
                 if owner_id is not None and int(player["id_участника"]) == int(owner_id)),
                None,
            )
            outline = QColor(self.TOKEN_COLORS[owner_index % len(self.TOKEN_COLORS)]) if owner_index is not None else QColor("#334155")
            painter.setPen(QPen(outline, 7 if owner_index is not None else 2))
            painter.setBrush(QColor(self.cell_color(cell)))
            painter.drawRoundedRect(rect, 12, 12)

            painter.setPen(QColor("#172033"))
            name = str(cell["название"])
            if len(name) > 18:
                name = name[:17] + "…"
            detail_top = 31
            cell_type = cell.get("тип")
            if cell_type in ("Улица", "Старт", "Шанс", "Коммунальная"):
                stripe_height = cell_height / 6
                border_inset = 7 if owner_index is not None else 2
                stripe = QRectF(
                    rect.left() + border_inset,
                    rect.top() + border_inset,
                    rect.width() - border_inset * 2,
                    stripe_height,
                )
                if int(cell.get("заложена") or 0):
                    stripe_color = "#9ca3af"
                elif cell_type == "Улица":
                    stripe_color = self.GROUP_COLORS.get(
                        str(cell.get("цветовая_группа")), "#cbd5e1"
                    )
                else:
                    stripe_color = self.CELL_STRIPE_COLORS.get(cell_type, "#cbd5e1")
                painter.setPen(Qt.NoPen)
                painter.setBrush(QColor(stripe_color))
                painter.drawRoundedRect(stripe, 7, 7)
                painter.drawRect(QRectF(stripe.left(), stripe.bottom() - 7, stripe.width(), 7))
                painter.setPen(QColor("#172033"))
                painter.setFont(QFont("DejaVu Sans", 10, QFont.Bold))
                painter.drawText(stripe.adjusted(5, 1, -5, -1), Qt.AlignCenter, name)
                detail_top = int(stripe_height + border_inset) + 4
            details = []
            if cell_type == "Старт":
                details.append(f'+{cell.get("бонус_старта") or 100} ₽ за полный круг')
            elif cell_type == "Шанс":
                details.extend(["Премия: +50 или +100 ₽", "Штраф: −50 или −100 ₽", "или перемещение"])
            if cell.get("цена_покупки") is not None:
                details.append(f'Цена: {cell["цена_покупки"]} ₽')
            if cell.get("владелец"):
                details.append(f'Владелец: {cell["владелец"]}')
            if int(cell.get("заложена") or 0):
                details.append("ЗАЛОЖЕНО · аренда 0 ₽")
            if cell.get("тип") == "Улица":
                level = int(cell.get("колво_домов") or 0)
                multiplier = int(cell.get("множитель_группы") or 1)
                if multiplier == 2:
                    details.append("Комплект группы: аренда ×2")
                rents = [
                    ("Без домов", cell.get("базовая_рента")),
                    ("1 дом", cell.get("рента_1_дом")),
                    ("2 дома", cell.get("рента_2_дома")),
                    ("Отель", cell.get("рента_отель")),
                ]
                for rent_level, (label, amount) in enumerate(rents):
                    marker = "▶" if rent_level == level else " "
                    shown_amount = int(amount) * multiplier if amount is not None else "—"
                    details.append(f"{marker} {label}: {shown_amount} ₽")
            elif not details:
                details.append(str(cell["тип"]))
            painter.setFont(QFont("DejaVu Sans", 9 if int(cell.get("заложена") or 0) else 11))
            painter.drawText(rect.adjusted(8, detail_top, -8, -7), Qt.AlignCenter | Qt.TextWordWrap, "\n".join(details))

        by_position = {}
        for player_index, player in enumerate(self.players):
            if player.get("код_статуса_участника") not in ("АКТИВЕН", "В_ЛОББИ"):
                continue
            participant_id = int(player["id_участника"])
            by_position.setdefault(
                self.display_positions.get(participant_id, int(player["позиция"])),
                [],
            ).append((player_index, player))
        for position, tokens in by_position.items():
            rect = next((item_rect for item_position, item_rect in self.cell_rects if item_position == position), None)
            if rect is None:
                continue
            direction_x = rect.center().x() - center.x()
            direction_y = rect.center().y() - center.y()
            length = max(1.0, math.hypot(direction_x, direction_y))
            outward = QPointF(direction_x / length, direction_y / length)
            tangent = QPointF(-outward.y(), outward.x())
            edge_distance = 1.0 / max(
                abs(outward.x()) / (cell_width / 2),
                abs(outward.y()) / (cell_height / 2),
            ) + 7
            for token_offset, (player_index, player) in enumerate(tokens):
                spread = (token_offset - (len(tokens) - 1) / 2) * 24
                arrow_tip = rect.center() + outward * edge_distance + tangent * spread
                arrow_base = arrow_tip + outward * 36
                participant_id = int(player["id_участника"])
                pen_width = 4 if participant_id == self.current_participant else 2
                painter.setPen(QPen(QColor("#ffffff"), pen_width))
                painter.setBrush(QColor(self.TOKEN_COLORS[player_index % len(self.TOKEN_COLORS)]))
                painter.drawPolygon(QPolygonF([
                    arrow_tip,
                    arrow_base + tangent * 16,
                    arrow_base - tangent * 16,
                ]))

        active_players = [player for player in self.players if player.get("код_статуса_участника") == "АКТИВЕН"]
        legend_y = center_rect.bottom() + 18
        painter.setFont(QFont("DejaVu Sans", 9, QFont.Bold))
        for index, player in enumerate(active_players):
            legend_x = center.x() - 130 + (index % 2) * 145
            row_y = legend_y + (index // 2) * 24
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(self.TOKEN_COLORS[index % len(self.TOKEN_COLORS)]))
            painter.drawRoundedRect(QRectF(legend_x, row_y, 16, 16), 4, 4)
            painter.setPen(QColor("#172033"))
            painter.drawText(QRectF(legend_x + 23, row_y - 2, 115, 20), Qt.AlignLeft | Qt.AlignVCenter, str(player["логин"]))


class CreateDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Создание комнаты")
        self.setMinimumWidth(420)
        form = QFormLayout(self)
        self.name = QLineEdit("Новая игра")
        count_widget = QWidget()
        count_layout = QHBoxLayout(count_widget)
        count_layout.setContentsMargins(0, 0, 0, 0)
        self.count_group = QButtonGroup(self)
        self.count_group.setExclusive(True)
        self.count_buttons = {}
        for count in (2, 3, 4):
            count_button = QPushButton(str(count))
            count_button.setObjectName("countChoice")
            count_button.setCheckable(True)
            count_button.setChecked(count == 4)
            self.count_group.addButton(count_button, count)
            self.count_buttons[count] = count_button
            count_layout.addWidget(count_button)
        self.password = QLineEdit()
        self.password.setEchoMode(QLineEdit.Password)
        self.password.setPlaceholderText("Необязательно")
        form.addRow("Название", self.name)
        form.addRow("Количество игроков", count_widget)
        form.addRow("Пароль", self.password)
        controls = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        controls.accepted.connect(self.accept)
        controls.rejected.connect(self.reject)
        form.addRow(controls)

    def player_count(self):
        return self.count_group.checkedId()


class StatsDialog(QDialog):
    def __init__(self, stats, leaders, history, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Статистика и рейтинг")
        self.resize(980, 680)
        layout = QVBoxLayout(self)
        title = QLabel("Статистика игроков")
        title.setObjectName("title")
        layout.addWidget(title)
        tabs = QTabWidget()
        overview = QWidget()
        overview_layout = QVBoxLayout(overview)
        stats_card = QFrame()
        stats_card.setObjectName("card")
        stats_form = QFormLayout(stats_card)
        stats_form.setContentsMargins(30, 24, 30, 24)
        stats_form.setHorizontalSpacing(36)
        stats_form.setVerticalSpacing(18)
        row = stats[0] if stats else {}
        metrics = [
            ("Игрок", row.get("логин", "—")),
            ("Завершено игр", row.get("количество_игр", 0)),
            ("Победы", row.get("победы", 0)),
            ("Процент побед", f'{row.get("процент_побед", 0)}%'),
            ("Любимая клетка", row.get("любимая_клетка") or "Пока нет данных"),
        ]
        self.stat_value_labels = {}
        for label, value in metrics:
            caption = QLabel(f"{label}:")
            caption.setStyleSheet("font-size:17px; font-weight:700; color:#475569;")
            number = QLabel(str(value))
            number.setStyleSheet("font-size:20px; font-weight:800; color:#1e3a8a;")
            number.setTextInteractionFlags(Qt.TextSelectableByMouse)
            stats_form.addRow(caption, number)
            self.stat_value_labels[label] = number
        overview_layout.addWidget(stats_card)
        overview_layout.addStretch()
        leader_rows = [{
            "Место": f"#{index}",
            "Игрок": leader["логин"],
            "Игр": leader["игры"],
            "Побед": leader["победы"],
            "Процент побед": f'{leader["процент"]}%',
        } for index, leader in enumerate(leaders, 1)]
        history_rows = [{
            "Игра": game["название"] if "название" in game else f'№{game["id_игры"]}',
            "Начало": game["дата_старта"].strftime("%d.%m.%Y %H:%M") if game.get("дата_старта") else "—",
            "Завершение": game["дата_завершения"].strftime("%d.%m.%Y %H:%M") if game.get("дата_завершения") else "—",
            "Баланс": f'{game["итоговый_баланс"]} ₽',
            "Победитель": game.get("победитель") or "—",
            "Результат": "🏆 Победа" if game.get("результат") == "Победа" else "Поражение",
        } for game in history]
        leaders_table = QTableWidget()
        history_table = QTableWidget()
        setup_table(leaders_table)
        setup_table(history_table)
        fill(leaders_table, leader_rows)
        fill(history_table, history_rows)
        leaders_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        history_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        tabs.addTab(overview, "Мои результаты")
        tabs.addTab(leaders_table, "Рейтинг")
        tabs.addTab(history_table, "История игр")
        layout.addWidget(tabs)
        layout.addWidget(button("Закрыть", self.accept, "primary"), alignment=Qt.AlignRight)


class MortgageDialog(QDialog):
    def __init__(self, properties, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Залог собственности для погашения долга")
        self.setMinimumWidth(680)
        self.checkboxes = []
        layout = QVBoxLayout(self)
        title = QLabel("Выберите объекты для залога")
        title.setObjectName("roomTitle")
        hint = QLabel(
            "Заложить можно только объект без построек, который ещё не заложен. "
            "Отметьте несколько объектов — итоговая сумма рассчитана автоматически."
        )
        hint.setWordWrap(True)
        layout.addWidget(title)
        layout.addWidget(hint)
        for item in properties:
            buildings = int(item["колво_домов"])
            if buildings > 0:
                amount = int(item.get("стоимость_продажи_уровня") or 0)
                action = "sell"
                description = f"продать 1 уровень из {buildings}"
            else:
                amount = int(item["залоговая_стоимость"])
                action = "mortgage"
                description = "заложить объект"
            checkbox = QCheckBox(
                f'{item["название"]}  •  {description}  •  получите {amount} ₽'
            )
            allowed = buildings > 0 or int(item["можно_заложить"]) == 1
            checkbox.setEnabled(allowed)
            checkbox.setProperty("ownership_id", int(item["id_владения"]))
            checkbox.setProperty("amount", amount)
            checkbox.setProperty("action", action)
            if not allowed:
                reason = "объект уже заложен"
                checkbox.setText(f"{checkbox.text()}  —  недоступно: {reason}")
            checkbox.toggled.connect(self.update_total)
            self.checkboxes.append(checkbox)
            layout.addWidget(checkbox)
        self.total_label = QLabel("Игрок получит: 0 ₽")
        self.total_label.setStyleSheet("font-size:20px; font-weight:800; color:#166534;")
        controls = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        controls.button(QDialogButtonBox.Ok).setText("Заложить выбранное")
        controls.button(QDialogButtonBox.Ok).setEnabled(False)
        controls.accepted.connect(self.accept)
        controls.rejected.connect(self.reject)
        self.controls = controls
        layout.addSpacing(12)
        layout.addWidget(self.total_label)
        layout.addWidget(controls)

    def update_total(self):
        total = sum(
            int(checkbox.property("amount"))
            for checkbox in self.checkboxes if checkbox.isChecked()
        )
        self.total_label.setText(f"Игрок получит: {total} ₽")
        self.controls.button(QDialogButtonBox.Ok).setEnabled(total > 0)

    def selected_ids(self):
        return [
            int(checkbox.property("ownership_id"))
            for checkbox in self.checkboxes if checkbox.isChecked()
        ]

    def selected_sales(self):
        return [
            int(checkbox.property("ownership_id"))
            for checkbox in self.checkboxes
            if checkbox.isChecked() and checkbox.property("action") == "sell"
        ]

    def selected_mortgages(self):
        return [
            int(checkbox.property("ownership_id"))
            for checkbox in self.checkboxes
            if checkbox.isChecked() and checkbox.property("action") == "mortgage"
        ]


class Window(QMainWindow):
    def __init__(self):
        super().__init__()
        self.resize(1760, 1060)
        self.setMinimumSize(1280, 800)
        self.setWindowTitle(f"Monopoly Lite · версия {APP_VERSION}")
        self.setStyleSheet(STYLE)
        self.db = Database()
        self.s = GameService(self.db)
        self.user = None
        self.part = None
        self.game = None
        self.state_row = {}
        self.last_action_id = 0
        self.last_message_id = 0
        self.state_version = -1
        self.displayed_action_ids = set()
        self.prompted_auctions = set()
        self.prompted_debt = None
        self.cached_board = []
        self.cached_players = []
        self.cached_lobby_players = []
        self.last_board_signature = None
        self.poll_count = 0
        self.disconnected = False
        self.snapshot_thread = None
        self.stack = QStackedWidget()
        self.setCentralWidget(self.stack)
        self.login_page = self.login_ui()
        self.rooms_page = self.rooms_ui()
        self.lobby_page = self.lobby_ui()
        self.game_page = self.game_ui()
        self.finish_page = self.finish_ui()
        for page in (self.login_page, self.rooms_page, self.lobby_page, self.game_page, self.finish_page):
            self.stack.addWidget(page)
        self.timer = QTimer(self)
        self.timer.setInterval(settings.poll_interval_ms)
        self.timer.timeout.connect(self.poll)
        self.timer.start()
        self.local_timer = QTimer(self)
        self.local_timer.setInterval(1000)
        self.local_timer.timeout.connect(self.tick_local_timer)
        self.local_timer.start()

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
        actions.addWidget(button("Правила", self.show_rules))
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
        self.players_panel = QWidget()
        self.player_cards_layout = QGridLayout(self.players_panel)
        self.player_cards_layout.setSpacing(16)
        self.player_cards_layout.setAlignment(Qt.AlignTop | Qt.AlignHCenter)
        self.lobby_player_cards = []
        top_controls = QHBoxLayout()
        top_controls.addWidget(button("Покинуть комнату", self.leave))
        top_controls.addStretch()
        bottom_controls = QHBoxLayout()
        self.delete_button = button("Удалить комнату", self.delete_room, "danger")
        bottom_controls.addWidget(self.delete_button)
        bottom_controls.addStretch()
        hint = QLabel("Когда в комнате минимум два игрока, в вашей карточке появляется кнопка готовности. После готовности всех начинается отсчёт 10 секунд.")
        hint.setWordWrap(True)
        hint.setObjectName("subtitle")
        layout.addWidget(self.lobby_title)
        layout.addWidget(self.lobby_info)
        layout.addLayout(top_controls)
        layout.addWidget(self.countdown)
        layout.addSpacing(8)
        layout.addWidget(QLabel("Игроки в комнате"))
        layout.addWidget(self.players_panel, 1)
        layout.addWidget(hint)
        layout.addLayout(bottom_controls)
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
        status_row = QHBoxLayout()
        self.turn_label = QLabel("Ожидание хода")
        self.turn_label.setObjectName("waitingTurn")
        self.balance_label = QLabel("Баланс: —")
        self.balance_label.setObjectName("balance")
        self.turn_timer_label = QLabel("Время хода: —")
        self.turn_timer_label.setObjectName("countdown")
        status_row.addWidget(self.turn_label, 2)
        status_row.addWidget(self.balance_label, 1)
        status_row.addWidget(self.turn_timer_label, 1)
        self.board = BoardWidget()
        left.addWidget(self.info)
        left.addLayout(status_row)
        left.addWidget(self.board, 1)
        leave_row = QHBoxLayout()
        self.leave_game_button = button("Покинуть игру", self.confirm_leave_game, "danger")
        leave_row.addWidget(self.leave_game_button)
        leave_row.addStretch()
        left.addLayout(leave_row)
        right.addWidget(QLabel("Доступные действия"))
        right.addWidget(button("Правила игры", self.show_rules))
        self.roll_button = button("🎲 Бросить кубик", self.roll, "primary")
        self.buy_button = button("Купить собственность", self.buy, "success")
        self.decline_buy_button = button("Отказаться — открыть аукцион", self.decline_buy)
        self.improve_button = button("Построить улучшение", self.improve, "success")
        self.decline_improve_button = button("Не улучшать", self.decline_improve)
        self.end_button = button("Завершить ход", self.end, "primary")
        self.properties_button = button("Управление собственностью", self.properties)
        self.bid_button = button("Сделать ставку на аукционе", self.bid, "success")
        self.action_buttons = [
            self.roll_button, self.buy_button, self.decline_buy_button,
            self.improve_button, self.decline_improve_button, self.end_button,
            self.properties_button, self.bid_button,
        ]
        for action_button in self.action_buttons:
            right.addWidget(action_button)
        self.log_toggle = button("▾ Журнал событий", self.toggle_action_log)
        right.addWidget(self.log_toggle)
        self.action_log = QTextEdit()
        self.action_log.setReadOnly(True)
        self.action_log.setMinimumHeight(170)
        right.addWidget(self.action_log, 2)
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
        main_layout.addLayout(left, 4)
        main_layout.addWidget(right_card, 1)
        return page

    def finish_ui(self):
        page = QWidget()
        outer = QVBoxLayout(page)
        outer.addStretch()
        card = QFrame()
        card.setObjectName("card")
        card.setMaximumWidth(700)
        card_layout = QVBoxLayout(card)
        card_layout.setContentsMargins(55, 45, 55, 45)
        trophy = QLabel("🏆")
        trophy.setAlignment(Qt.AlignCenter)
        trophy.setStyleSheet("font-size:72px;")
        self.winner_label = QLabel("Игра завершена")
        self.winner_label.setAlignment(Qt.AlignCenter)
        self.winner_label.setObjectName("title")
        self.finish_details = QLabel()
        self.finish_details.setAlignment(Qt.AlignCenter)
        self.finish_details.setObjectName("subtitle")
        self.finish_details.setWordWrap(True)
        exit_button = button("Выйти из завершённой игры", self.return_to_rooms, "primary")
        card_layout.addWidget(trophy)
        card_layout.addWidget(self.winner_label)
        card_layout.addWidget(self.finish_details)
        card_layout.addSpacing(18)
        card_layout.addWidget(exit_button)
        row = QHBoxLayout()
        row.addStretch()
        row.addWidget(card)
        row.addStretch()
        outer.addLayout(row)
        outer.addStretch()
        return page

    def alert(self, text, error=False):
        if not error:
            QMessageBox.information(self, "Monopoly", text)
            return
        clean = str(text).split("ORA-06512")[0].strip()
        clean = re.sub(r"ORA-\d+:\s*", "", clean).strip()
        box = QMessageBox(self)
        box.setIcon(QMessageBox.Warning)
        box.setWindowTitle("Действие сейчас недоступно")
        box.setText("Не удалось выполнить действие")
        box.setInformativeText(clean)
        box.setStandardButtons(QMessageBox.Ok)
        box.exec()

    def show_rules(self):
        dialog = QDialog(self)
        dialog.setWindowTitle("Правила Monopoly Lite")
        dialog.resize(720, 680)
        layout = QVBoxLayout(dialog)
        title = QLabel("Правила игры")
        title.setObjectName("title")
        rules = QTextEdit()
        rules.setReadOnly(True)
        rules.setPlainText(RULES_TEXT)
        rules.setStyleSheet("font-size:16px; line-height:1.35;")
        layout.addWidget(title)
        layout.addWidget(rules)
        layout.addWidget(button("Закрыть", dialog.accept, "primary"), alignment=Qt.AlignRight)
        dialog.exec()

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
            game_id = self.s.create_game(self.user, dialog.name.text(), dialog.player_count(), dialog.password.text())
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
        self.disconnected = False
        self.game = int(game_id)
        self.part = self.s.participant(self.user, self.game)
        self.state_row = {}
        self.cached_board = []
        self.cached_players = []
        self.last_board_signature = None
        self.last_action_id = 0
        self.last_message_id = 0
        self.state_version = -1
        self.displayed_action_ids = set()
        self.prompted_auctions = set()
        self.prompted_debt = None
        self.action_log.clear()
        self.chat.clear()
        self.stack.setCurrentWidget(self.lobby_page)
        self.lobby_title.setText("Подключение к комнате…")
        self.lobby_info.setText("Загружаем участников")
        self.poll(True)

    def toggle_ready(self):
        ready = bool(
            next(
                (int(row["готов"]) for row in self.cached_lobby_players
                 if int(row["id_участника"]) == self.part),
                0,
            )
        )
        self.act(lambda: self.s.ready(self.part, 0 if ready else 1))

    def poll(self, force=False):
        self.poll_count += 1
        if self.stack.currentWidget() is self.rooms_page:
            if self.poll_count % 5 == 0:
                self.refresh_rooms()
            return
        if self.stack.currentWidget() not in (self.lobby_page, self.game_page) or not self.part:
            return
        if self.snapshot_thread is not None and self.snapshot_thread.isRunning():
            return
        if force:
            self.state_version = -1
        self.snapshot_thread = SnapshotThread(
            self.part,
            self.last_action_id,
            self.last_message_id,
            self.state_version,
            not self.cached_board,
            self,
        )
        self.snapshot_thread.completed.connect(self.apply_snapshot)
        self.snapshot_thread.failed.connect(self.snapshot_failed)
        self.snapshot_thread.start()

    def snapshot_failed(self, message):
        if self.part:
            self.alert(message, True)

    def apply_snapshot(self, snapshot):
        if not self.part or not snapshot["state"]:
            return
        self.state_row = snapshot["state"][0]
        self.game = int(self.state_row["id_игры"])
        player_rows = snapshot["players"]
        self.cached_players = player_rows
        if snapshot["cells"]:
            self.cached_board = snapshot["cells"]
        if snapshot["ownerships"] and self.cached_board:
            ownerships = {int(row["id_клетки"]): row for row in snapshot["ownerships"]}
            for cell in self.cached_board:
                ownership = ownerships.get(int(cell["id_клетки"]))
                if ownership:
                    cell.update(ownership)
        self.state_version = int(self.state_row.get("state_version") or 0)
        self.update_action_log(snapshot["actions"])
        for message in snapshot["chat"]:
            self.chat.append(
                f'[{message["дата_время"]:%H:%M}] {message["логин"]}: {message["текст"]}'
            )
            self.last_message_id = max(self.last_message_id, int(message["id_сообщения"]))

        status = self.state_row["код_статуса_игры"]
        if status in ("ОЖИДАНИЕ", "ПРОВЕРКА_ГОТОВНОСТИ"):
            self.poll_lobby(status)
            return
        if status == "ЗАВЕРШЕНА":
            self.show_finished_game()
            return
        if status == "ЗАБРОШЕНА":
            self.return_to_rooms()
            return
        self.stack.setCurrentWidget(self.game_page)
        board_signature = (
            self.state_version,
            tuple((row["id_участника"], row["позиция"], row["код_статуса_участника"]) for row in player_rows),
            self.state_row.get("id_текущего_участника"),
            self.state_row.get("последний_кубик"),
            self.state_row.get("последняя_карта_шанса"),
        )
        if board_signature != self.last_board_signature:
            self.board.set_state(
                self.cached_board, player_rows,
                self.state_row.get("id_текущего_участника"),
                self.state_row.get("последний_кубик"),
                self.state_row.get("последняя_карта_шанса"),
            )
            self.last_board_signature = board_signature
        self.update_game_status(player_rows)
        self.handle_debt_dialog()
        if self.state_row.get("код_состояния_хода") == "ПРОВЕДЕНИЕ_АУКЦИОНА":
            self.handle_auction_invitation(player_rows)
        self.info.setText(
            f'{self.state_row["название"]} · {self.state_row["статус_игры"]} · '
            f'{self.state_row.get("состояние_хода") or "-"}'
        )

    def tick_local_timer(self):
        if not self.state_row:
            return
        key = (
            "секунд_до_старта"
            if self.state_row.get("код_статуса_игры") == "ПРОВЕРКА_ГОТОВНОСТИ"
            else "секунд_хода"
        )
        if self.state_row.get(key) is not None:
            self.state_row[key] = max(0, int(self.state_row[key]) - 1)
        if self.stack.currentWidget() is self.game_page and self.cached_players:
            self.update_game_status(self.cached_players)
        elif self.stack.currentWidget() is self.lobby_page:
            remaining = int(self.state_row.get("секунд_до_старта") or 0)
            if self.state_row.get("код_статуса_игры") == "ПРОВЕРКА_ГОТОВНОСТИ":
                self.countdown.setText(
                    f"Все готовы! Игра начнётся через {remaining} сек. Можно отменить готовность."
                )

    def show_finished_game(self):
        players = self.cached_players
        winner_id = self.state_row.get("id_победителя")
        winner = next(
            (row for row in players if winner_id is not None and int(row["id_участника"]) == int(winner_id)),
            None,
        )
        if winner:
            self.winner_label.setText(f'Победитель: {winner["логин"]}')
            self.finish_details.setText(
                f'Игра «{self.state_row["название"]}» завершена.\n'
                f'Итоговый баланс победителя: {winner["баланс"]} ₽'
            )
        else:
            self.winner_label.setText("Игра завершена без победителя")
            self.finish_details.setText(f'Игра «{self.state_row["название"]}» завершена.')
        self.stack.setCurrentWidget(self.finish_page)

    def update_game_status(self, players):
        current_id = self.state_row.get("id_текущего_участника")
        current = next((row for row in players if current_id is not None and int(row["id_участника"]) == int(current_id)), None)
        me = next((row for row in players if int(row["id_участника"]) == self.part), None)
        my_turn = current_id is not None and int(current_id) == self.part
        if my_turn:
            self.turn_label.setText("ВАШ ХОД")
            self.turn_label.setObjectName("yourTurn")
        else:
            self.turn_label.setText(f'Сейчас ходит: {current["логин"]}' if current else "Ожидание следующего хода")
            self.turn_label.setObjectName("waitingTurn")
        self.turn_label.style().unpolish(self.turn_label)
        self.turn_label.style().polish(self.turn_label)
        self.balance_label.setText(f'Ваш баланс: {me["баланс"]} ₽' if me else "Баланс: —")
        seconds = int(self.state_row.get("секунд_хода") or 0)
        self.turn_timer_label.setText(f"Время хода: {seconds // 60:02d}:{seconds % 60:02d}")
        self.update_action_buttons(my_turn, me)

    def update_action_buttons(self, my_turn, me):
        for action_button in self.action_buttons:
            action_button.hide()
            action_button.setEnabled(False)
        state = self.state_row.get("код_состояния_хода")
        state_buttons = {
            "ОЖИДАНИЕ_БРОСКА": [self.roll_button],
            "ОЖИДАНИЕ_ПОКУПКИ": [self.buy_button, self.decline_buy_button],
            "ОЖИДАНИЕ_УЛУЧШЕНИЯ": [self.improve_button, self.decline_improve_button],
            "ЗАВЕРШЕНИЕ_ХОДА": [self.end_button],
        }
        if my_turn:
            for action_button in state_buttons.get(state, []):
                action_button.show()
                action_button.setEnabled(True)
        if my_turn and state == "ОЖИДАНИЕ_УЛУЧШЕНИЯ" and me:
            current_cell = next(
                (cell for cell in self.cached_board if int(cell["позиция"]) == int(me["позиция"])),
                None,
            )
            if current_cell:
                level = int(current_cell.get("колво_домов") or 0)
                labels = ["1 дом", "2 дом", "отель"]
                label = labels[level]
                cost = current_cell.get("цена_дома")
                self.improve_button.setText(f"Купить {label} за {cost} ₽")
        has_mortgage = any(
            int(cell.get("id_владельца") or -1) == self.part and int(cell.get("заложена") or 0)
            for cell in self.cached_board
        )
        if my_turn and (state == "ПОКРЫТИЕ_ДОЛГА" or (state == "ОЖИДАНИЕ_БРОСКА" and has_mortgage)):
            self.properties_button.show()
            self.properties_button.setEnabled(True)

    @staticmethod
    def action_text(action):
        actor = action.get("логин") or "Банк"
        cell = f' · {action["клетка"]}' if action.get("клетка") else ""
        code = action.get("код_действия")
        descriptions = {
            "ОПЛАТА_АРЕНДЫ": (
                f'заплатил {action.get("получатель") or "владельцу"} аренду'
            ),
            "ПОКУПКА_СОБСТВЕННОСТИ": "приобрёл собственность",
            "ТАЙМ_АУТ": (
                "пропустил ход и получил штраф"
                if action.get("сумма") is not None
                else "получил второй тайм-аут и объявлен банкротом"
            ),
            "АУКЦИОН": "выиграл аукцион" if action.get("логин") else "аукцион завершён без победителя",
        }
        description = descriptions.get(code, action["действие"])
        if action.get("сумма") is None:
            amount = ""
        elif code == "БРОСОК_КУБИКА":
            amount = f' · выпало {action["сумма"]}'
        else:
            amount = f' · {action["сумма"]} ₽'
        return f'[{action["дата_время"]:%H:%M:%S}] {actor}: {description}{cell}{amount}'

    def update_action_log(self, actions):
        if not actions:
            return
        new_actions = [action for action in actions if int(action["id_действия"]) not in self.displayed_action_ids]
        if new_actions:
            scrollbar = self.action_log.verticalScrollBar()
            was_at_bottom = scrollbar.value() >= scrollbar.maximum() - 4
            for action in new_actions:
                self.action_log.append(self.action_text(action))
                self.displayed_action_ids.add(int(action["id_действия"]))
            if was_at_bottom:
                scrollbar.setValue(scrollbar.maximum())
            latest_text = self.action_text(new_actions[-1]).split("] ", 1)[-1]
            self.board.set_center_event(latest_text)
        rent_actions = [action for action in new_actions if action.get("код_действия") == "ОПЛАТА_АРЕНДЫ"]
        if rent_actions:
            action = rent_actions[-1]
            self.board.set_center_event(
                f'{action.get("логин") or "Игрок"} → {action.get("получатель") or "владелец"}\n'
                f'{action.get("сумма") or 0} ₽ аренды'
            )
        self.last_action_id = max(self.last_action_id, *(int(action["id_действия"]) for action in actions))

    def handle_auction_invitation(self, players):
        current_id = self.state_row.get("id_текущего_участника")
        if current_id is None or int(current_id) == self.part:
            return
        me = next((row for row in players if int(row["id_участника"]) == self.part), None)
        if not me or me.get("код_статуса_участника") != "АКТИВЕН":
            return
        if self.state_row.get("id_аукциона") is None:
            return
        auction_id = int(self.state_row["id_аукциона"])
        if self.state_row.get("моя_ставка") is not None or auction_id in self.prompted_auctions:
            return
        self.prompted_auctions.add(auction_id)
        start_price = int(self.state_row["старт_цена"])
        balance = int(me["баланс"])
        answer = QMessageBox.question(
            self,
            "Начался аукцион",
            f'{self.state_row["аукцион_клетка"]}\nСтартовая цена: {start_price} ₽\n'
            f'Ваш баланс: {balance} ₽\n\nХотите участвовать?',
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if answer != QMessageBox.Yes or balance < start_price:
            if answer == QMessageBox.Yes and balance < start_price:
                self.alert("Недостаточно денег даже для минимальной ставки.")
            self.act(lambda: self.s.bid(auction_id, self.part, 0))
            return
        amount, accepted = QInputDialog.getInt(
            self,
            "Ставка на аукционе",
            f"Введите ставку от {start_price} до {balance} ₽:",
            start_price,
            start_price,
            balance,
        )
        self.act(lambda: self.s.bid(auction_id, self.part, amount if accepted else 0))

    def handle_debt_dialog(self):
        state = self.state_row.get("код_состояния_хода")
        current_id = self.state_row.get("id_текущего_участника")
        if state != "ПОКРЫТИЕ_ДОЛГА" or current_id is None or int(current_id) != self.part:
            if state != "ПОКРЫТИЕ_ДОЛГА":
                self.prompted_debt = None
            return
        debt_key = (self.game, self.state_row.get("время_начала_хода"))
        if self.prompted_debt == debt_key:
            return
        self.prompted_debt = debt_key
        self.properties()

    def toggle_action_log(self):
        visible = not self.action_log.isHidden()
        self.action_log.setVisible(not visible)
        self.log_toggle.setText("▸ Журнал событий" if visible else "▾ Журнал событий")

    def poll_lobby(self, status):
        self.stack.setCurrentWidget(self.lobby_page)
        all_players = self.cached_players
        me = next((row for row in all_players if int(row["id_участника"]) == self.part), None)
        if not me or me["код_статуса_участника"] != "В_ЛОББИ":
            self.return_to_rooms()
            return
        players = [row for row in all_players if row["код_статуса_участника"] == "В_ЛОББИ"]
        self.cached_lobby_players = players
        enough = len(players) >= 2
        self.render_player_cards(players, enough)
        self.lobby_title.setText(self.state_row["название"])
        ready_count = sum(int(row["готов"]) for row in players)
        self.lobby_info.setText(f"Комната №{self.game}  •  игроков {len(players)}  •  готовы {ready_count}/{len(players)}")
        is_host = int(self.state_row["id_хоста"]) == self.user
        self.delete_button.setVisible(is_host)
        if status == "ПРОВЕРКА_ГОТОВНОСТИ":
            remaining = int(self.state_row.get("секунд_до_старта") or 0)
            self.countdown.setText(f"Все готовы! Игра начнётся через {remaining} сек. Можно отменить готовность.")
            self.countdown.show()
        else:
            self.countdown.hide()

    def render_player_cards(self, players, enough=False):
        while self.player_cards_layout.count():
            item = self.player_cards_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        self.lobby_player_cards = []
        maximum = int(self.state_row.get("макс_игроков") or len(players))
        for index in range(maximum):
            if index >= len(players):
                placeholder = QFrame()
                placeholder.setObjectName("playerCard")
                placeholder.setMinimumHeight(82)
                placeholder_layout = QHBoxLayout(placeholder)
                empty_icon = QLabel("+")
                empty_icon.setAlignment(Qt.AlignCenter)
                empty_icon.setFixedSize(48, 48)
                empty_icon.setStyleSheet("background:#e2e8f0; color:#64748b; border-radius:24px; font-size:25px;")
                empty_text = QLabel("Свободное место — ожидаем игрока")
                empty_text.setStyleSheet("color:#64748b; font-size:16px;")
                placeholder_layout.addWidget(empty_icon)
                placeholder_layout.addWidget(empty_text)
                placeholder_layout.addStretch()
                placeholder.setFixedSize(500, 92)
                self.player_cards_layout.addWidget(placeholder, index // 2, index % 2)
                self.lobby_player_cards.append(placeholder)
                continue
            player = players[index]
            ready = bool(int(player["готов"]))
            card = QFrame()
            card.setObjectName("readyCard" if ready else "playerCard")
            card.setFixedSize(500, 96)
            card_layout = QHBoxLayout(card)
            card_layout.setContentsMargins(18, 12, 18, 12)
            avatar = QLabel(str(player["логин"])[0].upper())
            avatar.setAlignment(Qt.AlignCenter)
            avatar.setFixedSize(58, 58)
            color = BoardWidget.TOKEN_COLORS[index % len(BoardWidget.TOKEN_COLORS)]
            avatar.setStyleSheet(f"background:{color}; color:white; border-radius:29px; font-size:24px; font-weight:800;")
            name = QLabel(str(player["логин"]))
            name.setStyleSheet("font-size:18px; font-weight:700;")
            text_column = QVBoxLayout()
            role = QLabel("Участник комнаты")
            role.setStyleSheet("color:#64748b; font-size:14px;")
            is_me = int(player["id_участника"]) == self.part
            if is_me and enough:
                status = button(
                    "Отменить готовность" if ready else "Я готов",
                    self.toggle_ready,
                    "danger" if ready else "success",
                )
            else:
                status = QLabel("✓ ГОТОВ" if ready else "Ожидает готовности")
                status.setAlignment(Qt.AlignCenter)
                status.setStyleSheet(
                    "color:#15803d; font-weight:800;" if ready
                    else "color:#64748b; font-weight:600;"
                )
            status.setFixedSize(190, 42)
            text_column.addWidget(name)
            text_column.addWidget(role)
            card_layout.addWidget(avatar)
            card_layout.addLayout(text_column)
            card_layout.addStretch()
            card_layout.addWidget(status)
            self.player_cards_layout.addWidget(card, index // 2, index % 2)
            self.lobby_player_cards.append(card)

    def return_to_rooms(self):
        self.part = self.game = None
        self.state_row = {}
        self.last_action_id = 0
        self.last_message_id = 0
        self.state_version = -1
        self.displayed_action_ids = set()
        self.prompted_auctions = set()
        self.prompted_debt = None
        self.cached_board = []
        self.cached_players = []
        self.last_board_signature = None
        self.stack.setCurrentWidget(self.rooms_page)
        self.refresh_rooms()

    def current_cell(self):
        me = next(row for row in self.cached_players if int(row["id_участника"]) == self.part)
        position = int(me["позиция"])
        return int(next(row["id_клетки"] for row in self.cached_board if int(row["позиция"]) == position))

    def roll(self):
        try:
            self.board.set_center_event(None)
            dice = self.s.roll(self.part)
            self.poll(True)
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def buy(self): self.act(lambda: self.s.buy(self.part, self.current_cell()))
    def decline_buy(self):
        self.act(lambda: self.s.decline_buy(self.part, self.current_cell()))
    def improve(self): self.act(lambda: self.s.improve(self.part, self.current_cell()))
    def decline_improve(self): self.act(lambda: self.s.decline_improve(self.part, self.current_cell()))
    def end(self): self.act(lambda: self.s.end(self.game))

    def properties(self):
        try:
            properties = self.s.props(self.part)
            state = self.state_row.get("код_состояния_хода")
            if state == "ПОКРЫТИЕ_ДОЛГА":
                if not properties:
                    self.alert("У вас нет собственности для погашения долга.")
                    return
                dialog = MortgageDialog(properties, self)
                if dialog.exec() == QDialog.Accepted:
                    def resolve_debt():
                        self.s.resolve_debt(
                            self.part,
                            dialog.selected_mortgages(),
                            dialog.selected_sales(),
                        )
                    self.act(resolve_debt)
                return
            else:
                properties = [row for row in properties if int(row["заложена"]) == 1]
            if not properties:
                self.alert(
                    "Сейчас нет доступных действий с собственностью.\n\n"
                    "Залог доступен только при отрицательном балансе. "
                    "Выкуп заложенного объекта доступен перед броском кубика."
                )
                return
            labels = [
                f'{row["id_владения"]}: {row["название"]} — заложено; '
                f'выкупить за {row["стоимость_выкупа"]} ₽'
                for row in properties
            ]
            item, accepted = QInputDialog.getItem(
                self,
                "Управление собственностью",
                "Выберите заложенный объект для выкупа:",
                labels,
                0,
                False,
            )
            if not accepted:
                return
            ownership_id = int(item.split(":")[0])
            self.act(lambda: self.s.redeem(self.part, ownership_id))
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

    def confirm_leave_game(self):
        answer = QMessageBox.question(
            self,
            "Покинуть игру?",
            "Вы станете банкротом, а вся собственность вернётся банку. Продолжить?",
            QMessageBox.Ok | QMessageBox.Cancel,
            QMessageBox.Cancel,
        )
        if answer == QMessageBox.Ok:
            self.leave()

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
            StatsDialog(
                self.s.stats(self.user),
                self.s.leaders(),
                self.s.history(self.user),
                self,
            ).exec()
        except DatabaseError as exc:
            self.alert(str(exc), True)

    def closeEvent(self, event):
        if self.snapshot_thread is not None and self.snapshot_thread.isRunning():
            self.snapshot_thread.wait(5000)
        self.disconnect_on_window_close()
        self.db.close()
        super().closeEvent(event)

    def changeEvent(self, event):
        super().changeEvent(event)
        if self.isMinimized():
            self.disconnect_on_window_close()

    def disconnect_on_window_close(self):
        if self.disconnected or not self.part:
            return
        self.disconnected = True
        try:
            status = self.state_row.get("код_статуса_игры")
            if status == "АКТИВНА" and hasattr(self.s, "disconnect"):
                self.s.disconnect(self.part)
            elif status in ("ОЖИДАНИЕ", "ПРОВЕРКА_ГОТОВНОСТИ"):
                self.s.leave_lobby(self.part)
        except (DatabaseError, AttributeError):
            pass
        self.part = self.game = None
        self.state_row = {}
        if self.user:
            self.stack.setCurrentWidget(self.rooms_page)


def main():
    app = QApplication(sys.argv)
    try:
        print(f"Запущена Monopoly Lite, версия интерфейса {APP_VERSION}")
        window = Window()
        window.showMaximized()
        return app.exec()
    except Exception as exc:
        QMessageBox.critical(None, "Ошибка", str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
