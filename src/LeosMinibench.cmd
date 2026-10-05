@echo off
setlocal
rem Leos Minibench starten (ohne exe). Das Skript fordert selbst Administratorrechte an
rem und legt Berichte, Vergleichsdatenbank und Laufzeitdaten im Ordner Minibench-Daten neben dieser Datei ab.
if not exist "%~dp0LeosMinibench.ps1" (
    echo.
    echo   LeosMinibench.ps1 fehlt. Beide Dateien muessen im selben Ordner liegen:
    echo   %~dp0
    echo.
    pause
    exit /b 1
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0LeosMinibench.ps1" -DatenDir "%~dp0Minibench-Daten"
exit /b 0
