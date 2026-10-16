@echo off
rem One-click launcher: starts duka_pos and opens it in the browser.
rem MySQL must be running first (start it from the XAMPP control panel).
cd /d "%~dp0"
start "" "http://127.0.0.1:8080"
py run.py
pause
