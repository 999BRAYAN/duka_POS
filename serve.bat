@echo off
rem Starts Duka POS (web, release build) at http://localhost:8080 and opens it.
setlocal
cd /d "%~dp0"
set PORT=8080

netstat -ano | findstr /r /c:":%PORT% .*LISTENING" >nul
if not errorlevel 1 (
  start "" http://localhost:%PORT%
  exit /b 0
)

if not exist "build\web\index.html" (
  echo Building Duka POS for the web, first run only - this takes a few minutes...
  call flutter build web --release || (pause & exit /b 1)
)

if not exist "build\serve.exe" (
  call dart compile exe tool\serve.dart -o build\serve.exe || (pause & exit /b 1)
)

start "" http://localhost:%PORT%
title Duka POS server - close this window to stop
echo Duka POS is running at http://localhost:%PORT%
echo Close this window to stop it.
"build\serve.exe" "build\web" %PORT%
