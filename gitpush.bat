@echo off
setlocal enabledelayedexpansion

:: Change to the folder where this .bat file lives
cd /d "%~dp0"

:: Use PowerShell to get a clean date/time string
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-Date -Format \"d MMMM yyyy h:mm tt\""') do set _msg=%%a

:: --- Git ---
git add .
git commit -m "%_msg%"
git push

echo.
echo Done!  Committed as: %_msg%
echo.
pause
