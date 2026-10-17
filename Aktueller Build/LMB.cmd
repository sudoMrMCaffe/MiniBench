@echo off
setlocal
rem Leos Minibench (LMB) starten.
rem Startet bevorzugt LMB.exe im selben Ordner; fehlt die exe, startet das PowerShell-Skript.
if exist "%~dp0LMB.exe" (
    start "" "%~dp0LMB.exe" %*
    exit /b 0
)
if exist "%~dp0LeosMinibench.exe" (
    start "" "%~dp0LeosMinibench.exe" %*
    exit /b 0
)
if not exist "%~dp0LeosMinibench.ps1" (
    echo.
    echo   Weder LMB.exe noch LeosMinibench.ps1 wurden gefunden.
    echo   Bitte LMB.exe oder LeosMinibench.ps1 im selben Ordner ablegen:
    echo   %~dp0
    echo.
    pause
    exit /b 1
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0LeosMinibench.ps1" -DatenDir "%~dp0Minibench-Daten" %*
exit /b 0
