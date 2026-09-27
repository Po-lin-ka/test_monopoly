@echo off
chcp 65001 >nul
cd /d "%~dp0" || exit /b 1
call ".venv\Scripts\activate.bat"
if errorlevel 1 goto failure
python -m app.main
if not errorlevel 1 exit /b 0
:failure
pause
exit /b 1
