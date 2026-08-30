@echo off
setlocal
if /I "%~1"=="--sem-memoria" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Agent.ps1" -ProjectPath "%CD%" -Mode Private %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %errorlevel%
)
if /I "%~1"=="--nova" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Agent.ps1" -ProjectPath "%CD%" -Mode Managed -Fresh %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %errorlevel%
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Agent.ps1" -ProjectPath "%CD%" -Mode Managed %*
exit /b %errorlevel%
