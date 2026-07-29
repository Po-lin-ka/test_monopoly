# Развёртывание Monopoly на Windows с минимальным расходом диска

Эта инструкция разворачивает на одном компьютере:

- Oracle AI Database Free Lite в Docker;
- схему `MONOPOLY` и PL/SQL-пакет игры;
- Python-клиент с интерфейсом PySide6.

Для экономии места используется официальный облегчённый образ Oracle `latest-lite`, а не полный образ.

---

## 1. Что потребуется

- Windows 10/11 x64;
- включённая виртуализация в BIOS/UEFI;
- не менее 8 ГБ оперативной памяти;
- Docker Desktop с WSL 2;
- Git;
- Python 3.11 или 3.12;
- несколько гигабайт свободного места для Docker, Oracle и Python-зависимостей.

Официальные инструкции:

- Docker Desktop: https://docs.docker.com/desktop/setup/install/windows-install/
- Oracle Free Lite в Docker: https://docs.oracle.com/en/database/oracle/agent-memory/26.6/guide/run-locally.html

> Все команды ниже выполняются в **PowerShell**.

---

## 2. Установить WSL 2

Откройте PowerShell от имени администратора:

```powershell
wsl --install
```

Перезагрузите Windows.

После перезагрузки проверьте:

```powershell
wsl --status
```

---

## 3. Установить Docker Desktop

Установите Docker Desktop для Windows и при установке оставьте выбранным режим WSL 2.

После запуска Docker Desktop проверьте в PowerShell:

```powershell
docker version
```

Команда должна показать клиент и сервер Docker.

### Экономия места

Используйте только образ `latest-lite`.

Если на диске `C:` мало места, в Docker Desktop перенесите расположение диска Docker на другой диск:

```text
Settings → Resources → Advanced → Disk image location
```

Не создавайте несколько контейнеров Oracle одновременно.

---

## 4. Скачать проект с GitHub

Перейдите в папку, где будет проект:

```powershell
cd C:\
```

Клонируйте репозиторий:

```powershell
git clone https://github.com/Po-lin-ka/test_monopoly.git monopoly
cd C:\monopoly
```

Переключитесь на ветку `test`:

```powershell
git switch test
git pull
```

Проверьте наличие файлов:

```powershell
Get-ChildItem
Get-ChildItem .\database
Get-ChildItem .\app
```

Основные папки:

```text
C:\monopoly
├── app
├── database
├── network_test
├── requirements.txt
└── .env.example
```

---

## 5. Скачать облегчённый Oracle

```powershell
docker pull container-registry.oracle.com/database/free:latest-lite
```

Создайте отдельный том для данных Oracle:

```powershell
docker volume create monopoly_oradata
```

Том сохраняет базу после остановки контейнера.

---

## 6. Запустить Oracle

```powershell
docker run -d --name monopoly-oracle --restart unless-stopped -p 1521:1521 -e ORACLE_PWD=MonopolyAdmin2026 -v monopoly_oradata:/opt/oracle/oradata container-registry.oracle.com/database/free:latest-lite
```

Проверьте запуск:

```powershell
docker ps
```

Смотрите журнал:

```powershell
docker logs -f monopoly-oracle
```

Дождитесь сообщения:

```text
DATABASE IS READY TO USE!
```

После этого нажмите `Ctrl+C`.

---

## 7. Создать пользователя MONOPOLY

Выполните в PowerShell:

```powershell
@"
CREATE USER monopoly IDENTIFIED BY "123321" QUOTA UNLIMITED ON USERS;
GRANT CREATE SESSION TO monopoly;
GRANT CREATE TABLE TO monopoly;
GRANT CREATE VIEW TO monopoly;
GRANT CREATE PROCEDURE TO monopoly;
GRANT CREATE TYPE TO monopoly;
GRANT CREATE SEQUENCE TO monopoly;
GRANT CREATE TRIGGER TO monopoly;
EXIT;
"@ | docker exec -i monopoly-oracle sqlplus system/MonopolyAdmin2026@FREEPDB1
```

Параметры приложения:

```text
Логин Oracle: monopoly
Пароль Oracle: 123321
Сервис: FREEPDB1
Порт: 1521
```

Если Oracle отклонит слишком простой пароль, задайте более сложный и укажите тот же пароль в `.env`.

---

## 8. Загрузить SQL-файлы в контейнер

Находясь в `C:\monopoly`, выполните:

```powershell
docker exec monopoly-oracle sh -lc "rm -rf /tmp/database && mkdir -p /tmp/database"
docker cp .\database\. monopoly-oracle:/tmp/database/
```

Проверьте:

```powershell
docker exec monopoly-oracle ls -la /tmp/database
```

Должны быть видны:

```text
01_drop_objects.sql
02_create_tables.sql
03_insert_dictionaries.sql
04_insert_cells.sql
05_insert_chance_cards.sql
06_create_types.sql
07_package_spec.sql
08_package_body.sql
09_views.sql
10_tests.sql
install.sql
```

---

## 9. Установить базу игры

```powershell
docker exec -it monopoly-oracle sh -lc "cd /tmp/database && sqlplus monopoly/123321@FREEPDB1 @install.sql"
```

В конце ожидается:

```text
Package created.
Package body created.
No errors.
Установка завершена.
```

При ошибке `SP2-0310` проверьте, что команда запускается именно из `/tmp/database`.

---

## 10. Проверить базу

```powershell
@"
SET PAGESIZE 100
SELECT object_name, object_type, status
FROM user_objects
WHERE object_name = 'MONOPOLY'
ORDER BY object_type;

SELECT COUNT(*) AS cells_count FROM "КЛЕТКИ";
SELECT COUNT(*) AS cards_count FROM "КАРТЫ_ШАНСА";
EXIT;
"@ | docker exec -i monopoly-oracle sqlplus monopoly/123321@FREEPDB1
```

Правильный результат:

```text
MONOPOLY    PACKAGE         VALID
MONOPOLY    PACKAGE BODY    VALID

CELLS_COUNT
-----------
12

CARDS_COUNT
-----------
10
```

---

## 11. Установить Python-зависимости

```powershell
cd C:\monopoly
py -3 -m venv .venv
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

---

## 12. Создать файл `.env`

```powershell
Copy-Item .env.example .env
notepad .env
```

Содержимое:

```env
ORACLE_USER=monopoly
ORACLE_PASSWORD=123321
ORACLE_DSN=localhost:1521/FREEPDB1
POLL_INTERVAL_MS=1000
```

Сохраните файл.

---

## 13. Проверить соединение Python с Oracle

```powershell
cd C:\monopoly
.\.venv\Scripts\Activate.ps1
$env:PYTHONPATH="."
python .\network_test\test_oracle.py
```

Ожидается:

```text
Пользователь: MONOPOLY
Дата Oracle: ...
Клеток: 12
Карт шанса: 10
```

---

## 14. Запустить игру

```powershell
cd C:\monopoly
.\.venv\Scripts\Activate.ps1
python -m app.main
```

Для проверки двух игроков откройте второе окно PowerShell и повторите:

```powershell
cd C:\monopoly
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
python -m app.main
```

В первом окне зарегистрируйте `player1`, во втором — `player2`.

---

## 15. Запуск после перезагрузки Windows

1. Запустите Docker Desktop.
2. Проверьте контейнер:

```powershell
docker ps
```

Если контейнер остановлен:

```powershell
docker start monopoly-oracle
```

Затем:

```powershell
cd C:\monopoly
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
python -m app.main
```

---

## 16. Остановка для экономии памяти

После работы закройте игру и остановите Oracle:

```powershell
docker stop monopoly-oracle
```

Данные останутся в томе `monopoly_oradata`.

Для следующего запуска:

```powershell
docker start monopoly-oracle
```

---

## 17. Безопасная очистка диска Docker

Посмотреть использование диска:

```powershell
docker system df
```

Удалить неиспользуемый кэш сборки:

```powershell
docker builder prune -f
```

Удалить неиспользуемые образы, не связанные с контейнерами:

```powershell
docker image prune -f
```

> Не выполняйте `docker system prune --volumes`: команда может удалить том с базой.

Не удаляйте том:

```text
monopoly_oradata
```

---

## 18. Полное удаление

Только если база больше не нужна:

```powershell
docker stop monopoly-oracle
docker rm monopoly-oracle
docker volume rm monopoly_oradata
docker rmi container-registry.oracle.com/database/free:latest-lite
Remove-Item -Recurse -Force C:\monopoly
```

Удаление тома безвозвратно удаляет данные игры.

---

## Краткий ежедневный запуск

```powershell
docker start monopoly-oracle
cd C:\monopoly
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
python -m app.main
```

## Краткая остановка

```powershell
docker stop monopoly-oracle
```
