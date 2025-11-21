REM Da dieses Skript einen zugang zum Github-Repository benötigt, ist es nicht möglich, dies ohne zugänglichem Account zu tun.
REM Bitte stellen Sie sicher, dass Sie Zugriff auf das Repository haben, bevor Sie dieses Skript ausführen.

REM Description: This script downloads a GitHub repository as a zip file,
REM              extracts it, navigates into the extracted folder, and runs
REM              the run.cmd script located in the PowerShell Scripts directory.

@echo off
setlocal EnableExtensions
set "PAUSE_ON_ERROR=1"

REM Download the repository as a zip file
set "REPO_URL=https://github.com/TheLionDeveloper44/TBZ_M122-Projekt/archive/refs/heads/main.zip"
set "ZIP_FILE=temp_repo.zip"
set "EXTRACT_DIR=temp_repo"

echo Downloading repository from %REPO_URL% ...
powershell -command "try { Invoke-WebRequest -Uri '%REPO_URL%' -OutFile '%ZIP_FILE%' -ErrorAction Stop } catch { Write-Error ('Download failed: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 call :ExitOnError "Error: Unable to download the repository." "Verify the URL or your internet connection."

echo Extracting archive to %EXTRACT_DIR% ...
powershell -command "try { Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%EXTRACT_DIR%' -Force -ErrorAction Stop } catch { Write-Error ('Extraction failed: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 call :ExitOnError "Error: Unable to extract the archive." "Ensure the downloaded file is valid."

if not exist "%EXTRACT_DIR%\TBZ_M122-Projekt-main" (
    echo Error: Expected repository directory not found after extraction.
    exit /b 1
)

echo Changing into the extracted repository...
cd /d "%EXTRACT_DIR%\TBZ_M122-Projekt-main"
if errorlevel 1 call :ExitOnError "Error: Unable to enter the extracted repository." "Confirm the folder structure inside the zip."

REM Verify that the directories and contents are fetched
if not exist "PowerShell Scripts" (
    echo Error: PowerShell Scripts directory not found.
    exit /b 1
)
if not exist "Python Scripts" (
    echo Error: Python Scripts directory not found.
    exit /b 1
)

REM Check if run.cmd exists in PowerShell Scripts
if not exist "PowerShell Scripts\run.cmd" (
    echo Error: run.cmd not found in PowerShell Scripts.
    exit /b 1
)

echo Running PowerShell Scripts\run.cmd ...
cd "PowerShell Scripts"
call run.cmd
if errorlevel 1 call :ExitOnError "run.cmd reported a non-zero exit code." "Review the messages above for details."

REM Clean up temp_repo and zip if needed (optional, uncomment if desired)
REM cd ..\..
REM rd /s /q temp_repo
REM del temp_repo.zip

REM del temp_repo.zip

exit /b 0

+:ExitOnError
echo(
echo %~1
if not "%~2"=="" echo %~2
echo For troubleshooting, review the command output above.
if /I "%PAUSE_ON_ERROR%"=="1" pause
exit /b 1