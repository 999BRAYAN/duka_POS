@echo off
rem One-click launcher: starts MySQL if it isn't running, starts duka_pos, and
rem opens the browser the moment the server is ready.
cd /d "%~dp0"

netstat -ano | findstr /r /c:":3306 .*LISTENING" >nul
if errorlevel 1 (
  if exist "C:\xampp\mysql\bin\mysqld.exe" (
    echo Starting MySQL...
    powershell -NoProfile -Command "Start-Process -WindowStyle Hidden 'C:\xampp\mysql\bin\mysqld.exe' '--defaults-file=C:\xampp\mysql\bin\my.ini --standalone'"
  )
)

set DUKA_OPEN_BROWSER=1
py run.py
if errorlevel 1 pause
