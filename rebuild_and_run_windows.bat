@echo off
setlocal
cd /d "%~dp0"

echo [1/5] Closing old virtual environment...
if exist ".venv" (
    rmdir /s /q ".venv"
    if exist ".venv" (
        echo Failed to remove .venv. Close Python and the game, then run this file again.
        pause
        exit /b 1
    )
)

echo [2/5] Creating a fresh virtual environment...
py -3 -m venv .venv
if errorlevel 1 goto :error

echo [3/5] Updating pip...
call .venv\Scripts\activate.bat
python -m pip install --upgrade pip
if errorlevel 1 goto :error

echo [4/5] Installing dependencies...
python -m pip install -r requirements.txt
if errorlevel 1 goto :error

if not exist ".env" (
    copy ".env.example" ".env" >nul
    echo Created .env from .env.example. Check Oracle settings if the database is on another PC.
)

echo [5/5] Starting Monopoly Lite...
python -m app.main
exit /b %errorlevel%

:error
echo.
echo Environment rebuild failed. See the error above.
pause
exit /b 1
