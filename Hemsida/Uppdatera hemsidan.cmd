@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uppdatera.ps1"
if errorlevel 1 (
    pause
    exit /b 1
)
start "" "%~dp0index.html"
