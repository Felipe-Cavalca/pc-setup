@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-Agent.ps1"
set "agent_exit=%errorlevel%"
if not "%agent_exit%"=="0" pause
exit /b %agent_exit%
