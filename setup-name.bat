@echo off
rem One-time setup: lets you open the POS as  http://campusbites  instead of
rem  http://127.0.0.1:8765 . Needs administrator rights (it edits the hosts file
rem and adds a port-80 -> POS-port forward). Run it once; it is safe to re-run.
rem To undo:  setup-name.bat remove
setlocal
set NAME=campusbites
set PORT=8765
for /f "tokens=2 delims==" %%p in ('findstr /b /c:"DUKA_PORT=" "%~dp0.env" 2^>nul') do set PORT=%%p

net session >nul 2>&1
if errorlevel 1 (
  echo Asking for administrator rights...
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0' -ArgumentList '%*'"
  exit /b
)

set HOSTS=%SystemRoot%\System32\drivers\etc\hosts
findstr /v /r /c:"[ 	]%NAME%$" "%HOSTS%" > "%TEMP%\hosts.new"
netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=80 >nul 2>&1

if /i "%1"=="remove" (
  copy /y "%TEMP%\hosts.new" "%HOSTS%" >nul
  echo Removed. http://%NAME% no longer works.
  pause
  exit /b
)

>> "%TEMP%\hosts.new" echo 127.0.0.1 %NAME%
copy /y "%TEMP%\hosts.new" "%HOSTS%" >nul
netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=80 connectaddress=127.0.0.1 connectport=%PORT%
ipconfig /flushdns >nul
echo.
echo Done. Start the POS with start.bat, then open  http://%NAME%
pause
