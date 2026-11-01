@echo off
setlocal
cd /d "%~dp0"
set "ex03_python=python"
if exist "D:\Anaconda3\python.exe" set "ex03_python=D:\Anaconda3\python.exe"
if "%~1"=="--check" goto check
echo Opening the masked key entry and download status window...
"%ex03_python%" "R\ridership-ui.py"
set "ex03_result=%errorlevel%"
echo.
if not "%ex03_result%"=="0" echo No completed download in this run. Use the API Access Key email for the next attempt.
if "%ex03_result%"=="0" echo Download completed. You can return to the coursework chat.
pause
exit /b %ex03_result%
:check
"%ex03_python%" "R\acquire-ridership.py" --check
exit /b %errorlevel%
