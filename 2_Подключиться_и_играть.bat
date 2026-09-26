@echo off
setlocal
chcp 65001 >nul
pushd "%~dp0"
if errorlevel 1 goto folder_error
py -3.12 -c "import struct; assert struct.calcsize('P') == 8" >nul 2>&1
if not errorlevel 1 goto launcher
python -c "import sys,struct; assert sys.version_info[:2] == (3,12) and struct.calcsize('P') == 8" >nul 2>&1
if not errorlevel 1 goto python
 echo Нужен установленный Python 3.12 x64. Python Launcher или python должен быть доступен.
 echo Установите Python 3.12 с python.org с опцией Add python.exe to PATH и повторите запуск.
 echo На учебном компьютере без прав установки обратитесь к администратору.
goto failure
:launcher
py -3.12 "launcher\windows.py" join
if errorlevel 1 goto failure
goto success
:python
python "launcher\windows.py" join
if errorlevel 1 goto failure
:success
popd
exit /b 0
:failure
echo.
echo Игра не запущена или завершилась с ошибкой. Сохраните сообщение выше.
pause
popd
exit /b 1
:folder_error
echo Распакуйте проект в доступную папку перед запуском.
pause
exit /b 1
