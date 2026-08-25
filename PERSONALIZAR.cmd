@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-Personalization.ps1"
set "pcsetup_exit=%errorlevel%"
if not "%pcsetup_exit%"=="0" pause
exit /b %pcsetup_exit%
