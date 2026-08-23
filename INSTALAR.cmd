@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-PcSetupUpdate.ps1" -LauncherName INSTALAR.cmd
exit /b %errorlevel%
