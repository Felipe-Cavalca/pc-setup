@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\New-PcSetupMachineSummary.ps1"
set "pcsetup_exit=%errorlevel%"
pause
exit /b %pcsetup_exit%
