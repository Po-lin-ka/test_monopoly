@echo off
setlocal
chcp 65001 >nul
pushd "%~dp0"
if errorlevel 1 exit /b 1
if not exist ".venv-windows\Scripts\python.exe" goto no_environment
if not exist .env goto no_config
".venv-windows\Scripts\python.exe" -m app.main
if errorlevel 1 goto failure
popd
exit /b 0
:no_environment
echo Сначала запустите 1_Подготовить_окружение.bat.
goto failure
:no_config
echo Скопируйте .env.example в .env и заполните параметры Oracle.
:failure
echo Игра не запущена или завершилась с ошибкой. Сохраните сообщение выше.
pause
popd
exit /b 1
