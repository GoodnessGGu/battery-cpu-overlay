@echo off
set "DIR=%~dp0"
if exist "%DIR%Launch.vbs" (
    start "" wscript.exe "%DIR%Launch.vbs"
) else (
    start "" powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%DIR%BatteryOverlay.ps1"
)
