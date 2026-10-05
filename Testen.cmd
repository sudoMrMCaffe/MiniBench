@echo off
setlocal
title Leos Minibench testen
rem Führt die Pester-Tests aus. Ändert nichts am Aktuellen Build. Testen.cmd -Gesamtlauf prüft zusätzlich ganze Läufe.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Testen.ps1" %*
echo.
pause
