@echo off
rem Vice City Skate: first-time setup, then starts the game. See "1 - READ ME FIRST.txt".
title Vice City Skate
if not exist "%~dp0Files\setup\setup.ps1" (
    echo.
    echo   Vice City Skate is not unzipped yet.
    echo.
    echo   Close this window, right-click the "Vice City Skate" zip file,
    echo   choose "Extract All...", then open the extracted folder and
    echo   double-click "2 - Play Vice City Skate" from there.
    echo.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Files\setup\setup.ps1" %*
if errorlevel 1 (
    echo.
    pause
)
