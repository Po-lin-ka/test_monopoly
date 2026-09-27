@echo off
chcp 65001 >nul
cd /d "%~dp0" || exit /b 1
.venv\Scripts\python.exe -m app.main
if not errorlevel 1 exit /b 0
pause
exit /b 1
