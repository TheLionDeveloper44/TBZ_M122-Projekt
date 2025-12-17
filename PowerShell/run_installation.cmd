@echo off
setlocal
set "SCRIPT_DIR=%~dp0"

:: Check for admin privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :admin
) else (
    echo Anforderung von Administratorrechten...
    powershell -NoProfile -Command "try { Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','\"\"%~f0\"\" %*' -Verb RunAs } catch { Start-Process -WindowStyle Hidden -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%SCRIPT_DIR%run_ui-failed.ps1'; exit 1 }"
    if errorlevel 1 exit /b %errorlevel%
    exit /b
)

:: Run the main script with admin privileges, if elevated
:admin
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -STA -File "%SCRIPT_DIR%main_runinstaller.ps1" %*
exit /b %ERRORLEVEL%