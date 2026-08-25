@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-Verify.ps1"
set "pcsetup_exit=%errorlevel%"
exit /b %pcsetup_exit%
