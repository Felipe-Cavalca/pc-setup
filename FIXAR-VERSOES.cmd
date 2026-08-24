@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Save-PcSetupKnownGood.ps1" -ExportLock
set "pcsetup_exit=%errorlevel%"
pause
exit /b %pcsetup_exit%
