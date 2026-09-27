@echo off
setlocal
chcp 65001 >nul
pushd "%~dp0"
if errorlevel 1 exit /b 1
if exist ".venv-windows\Scripts\python.exe" goto install
py -3.12 -c "import struct; assert struct.calcsize('P') == 8" >nul 2>&1
if not errorlevel 1 goto py_launcher
python -c "import sys,struct; assert sys.version_info[:2] == (3,12) and struct.calcsize('P') == 8" >nul 2>&1
if not errorlevel 1 goto python
 echo Нужен Python 3.12 x64. Установите его с опцией Add python.exe to PATH.
goto failure
:py_launcher
py -3.12 -m venv .venv-windows
if errorlevel 1 goto failure
goto install
:python
python -m venv .venv-windows
if errorlevel 1 goto failure
:install
".venv-windows\Scripts\python.exe" -c "import sys,struct; assert sys.version_info[:2] == (3,12) and struct.calcsize('P') == 8"
if errorlevel 1 goto wrong_version
".venv-windows\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 goto failure
if exist .env goto success
copy /y .env.example .env >nul
if errorlevel 1 goto failure
:success
echo Окружение готово. Укажите параметры Oracle в файле .env.
pause
popd
exit /b 0
:wrong_version
echo В .venv-windows другое окружение. Переименуйте эту папку и повторите запуск.
:failure
echo Подготовка не завершена. Сохраните сообщение об ошибке выше.
pause
popd
exit /b 1
