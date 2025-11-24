@echo off
setlocal

:: Check for admin privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :admin
) else (
    echo Anforderung von Administratorrechten...
    powershell "start-process '%~f0' -verb runas"
    exit /b
)

:admin
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -STA -File "%SCRIPT_DIR%main.ps1" %*
exit /b %ERRORLEVEL%