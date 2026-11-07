@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uppdatera.ps1"
if errorlevel 1 (
    pause
    exit /b 1
)
cd /d "%~dp0.."
git add Hemsida
git commit -m "Uppdatera krönikan"
git push
echo.
echo Klart! Sidan uppdateras på https://lusse.github.io/dagbok/ inom en minut eller två.
pause
