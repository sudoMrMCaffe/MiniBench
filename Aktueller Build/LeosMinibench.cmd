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
set "PS_EXE="
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PS_EXE if exist "%LOCALAPPDATA%\Microsoft\PowerShell\pwsh.exe" set "PS_EXE=%LOCALAPPDATA%\Microsoft\PowerShell\pwsh.exe"
if not defined PS_EXE (
    where.exe pwsh.exe >nul 2>&1
    if not errorlevel 1 set "PS_EXE=pwsh.exe"
)
if not defined PS_EXE set "PS_EXE=powershell.exe"

start "" "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0LeosMinibench.ps1" -DatenDir "%~dp0Minibench-Daten"
exit /b 0
