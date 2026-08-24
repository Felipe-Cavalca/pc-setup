@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Invoke-PcSetupBackup.ps1" -Action Verify
set "pcsetup_exit=%errorlevel%"
pause
exit /b %pcsetup_exit%
