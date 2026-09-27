@echo off
chcp 65001 >nul
cd /d "%~dp0" || exit /b 1
py -3.12 -m venv .venv
if errorlevel 1 goto failure
.venv\Scripts\python.exe -m pip install -r requirements.txt
if errorlevel 1 goto failure
echo Окружение готово. Параметры Oracle укажите в .env.
pause
exit /b 0
:failure
pause
exit /b 1
