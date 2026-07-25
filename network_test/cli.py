import os
import sys

import oracledb
from dotenv import load_dotenv


load_dotenv()


def create_connection() -> oracledb.Connection:
    """Подключается к Oracle по настройкам из файла .env."""
    dsn = oracledb.makedsn(
        host=os.environ["ORACLE_HOST"],
        port=int(os.getenv("ORACLE_PORT", "1521")),
        service_name=os.environ["ORACLE_SERVICE"],
    )

    return oracledb.connect(
        user=os.environ["ORACLE_USER"],
        password=os.environ["ORACLE_PASSWORD"],
        dsn=dsn,
    )


def show_messages(connection: oracledb.Connection) -> None:
    """Получает и выводит все сообщения общей тестовой таблицы."""
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                id,
                sender_name,
                message_text,
                sent_at
            FROM network_test_messages
            ORDER BY id
            """
        )

        messages = cursor.fetchall()

    print("\nОбщие сообщения")
    print("-" * 70)

    if not messages:
        print("Сообщений пока нет.")
    else:
        for message_id, sender, text, sent_at in messages:
            print(
                f"{message_id:>3} | "
                f"{sent_at:%d.%m.%Y %H:%M:%S} | "
                f"{sender}: {text}"
            )

    print("-" * 70)


def send_message(
    connection: oracledb.Connection,
    message_text: str,
) -> None:
    """Записывает сообщение в Oracle и фиксирует транзакцию."""
    sender_name = os.environ["CLIENT_NAME"]

    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO network_test_messages (
                sender_name,
                message_text
            )
            VALUES (
                :sender_name,
                :message_text
            )
            """,
            sender_name=sender_name,
            message_text=message_text,
        )

    connection.commit()


def run_client() -> None:
    """Показывает консольное меню тестового клиента."""
    with create_connection() as connection:
        print("Подключение к Oracle успешно.")
        print(f"Имя клиента: {os.environ['CLIENT_NAME']}")

        while True:
            print("\n1 — показать сообщения")
            print("2 — отправить сообщение")
            print("0 — выйти")

            choice = input("Выберите действие: ").strip()

            if choice == "1":
                show_messages(connection)

            elif choice == "2":
                message_text = input("Введите сообщение: ").strip()

                if not message_text:
                    print("Пустое сообщение не отправлено.")
                    continue

                if len(message_text) > 200:
                    print("Сообщение не должно превышать 200 символов.")
                    continue

                send_message(connection, message_text)
                print("Сообщение сохранено в Oracle.")

            elif choice == "0":
                print("Клиент завершён.")
                return

            else:
                print("Введите 0, 1 или 2.")


def main() -> int:
    try:
        run_client()
        return 0

    except KeyError as error:
        print(f"В файле .env отсутствует настройка: {error}")
        return 1

    except oracledb.Error as error:
        print(f"Ошибка Oracle: {error}")
        return 1

    except KeyboardInterrupt:
        print("\nКлиент остановлен.")
        return 0


if __name__ == "__main__":
    sys.exit(main())