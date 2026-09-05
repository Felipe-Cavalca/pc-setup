@echo off
setlocal
set "agent_project=%CD%"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-Agent.ps1" -ProjectPath "%agent_project%" %*
set "agent_exit=%errorlevel%"
if not "%agent_exit%"=="0" pause
exit /b %agent_exit%
