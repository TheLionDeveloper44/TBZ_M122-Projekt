# Author: TheLionDeveloper44
# Dieses Skript unterliegt der Lizenz, die in der LICENSE-Datei im Stammverzeichnis dieses Repositories enthalten ist.
# Ohne ausdrückliche schriftliche Genehmigung ist es untersagt, dieses Skript zu kopieren, zu modifizieren oder zu verbreiten.

# Check if running as administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Load Windows Forms assembly
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $ScriptDir = (Get-Location).Path
} else {
    $ScriptDir = Split-Path -Parent $ScriptPath
}
$LogFile = Join-Path $ScriptDir "log.txt"

function Write-Log {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $entry = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try {
        Add-Content -Path $LogFile -Value $entry -Encoding UTF8
    } catch {
        Write-Warning "Unable to write to log file: $($_.Exception.Message)"
    }
}

# Load UI module (separated UI code)
. "$ScriptDir\ui_runner.ps1"

function Show-UiStartupSplash {
    param([string]$Message = "InstallCraft UI wird initialisiert...")
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "InstallCraft"
    $form.Size = New-Object System.Drawing.Size(320, 140)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedToolWindow'
    $form.ControlBox = $false
    $form.TopMost = $true
    $label = New-Object System.Windows.Forms.Label
    $label.Dock = 'Fill'
    $label.TextAlign = 'MiddleCenter'
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
    $label.Text = $Message
    $form.Controls.Add($label)
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    return $form
}
function Close-UiStartupSplash {
    param([System.Windows.Forms.Form]$Form)
    if (-not $Form -or $Form.IsDisposed) { return }
    try { $Form.Close() } catch {}
    $Form.Dispose()
}

Write-Log "----- Installer run started. Admin rights: $IsAdmin -----"

# Check Internet availability
$InternetTestUri = "https://www.google.com"
$InternetAvailable = $true
Write-Log "Checking internet connectivity via $InternetTestUri"
try {
    $request = [System.Net.WebRequest]::Create($InternetTestUri)
    $request.Method = "HEAD"
    $request.Timeout = 5000
    $response = $request.GetResponse()
    $response.Close()
    Write-Log "Internet connectivity confirmed."
} catch {
    $InternetAvailable = $false
    Write-Log "No internet connection detected. Installation aborted."
}
if (-not $InternetAvailable) {
    [System.Windows.Forms.MessageBox]::Show("Keine Internetverbindung. Installation wird beendet.", "Internet Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Write-Log "Exiting because no internet connection is available."
    exit
}

if ($IsAdmin) {
    Write-Log "Launching enhanced installation UI."
    $MuSoLibDir = Join-Path (Split-Path -Parent $ScriptDir) "MuSoLIB"
    if (Test-Path $MuSoLibDir) {
        Write-Log "MuSoLIB audio directory found at $MuSoLibDir"
    } else {
        Write-Log "MuSoLIB audio directory missing at $MuSoLibDir"
        $MuSoLibDir = $null
    }
    $splashForm = Show-UiStartupSplash -Message "InstallCraft UI wird initialisiert..."
    try {
        Start-InstallUI -Title "InstallCraft - The Ultimate Installer" -MediaRoot $MuSoLibDir
        Wait-InstallUiReady -TimeoutMs 15000 | Out-Null
    } finally {
        Close-UiStartupSplash -Form $splashForm
    }
    Update-Ui -Progress 5 -Message "Initialising Oberfläche"

    # Get the script directory and set paths
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ParentDir = Split-Path -Parent $ScriptDir
    $ApplicationsDir = Join-Path $ParentDir "Applications"
    $PythonDir = Join-Path $ApplicationsDir "Python"

    # Create Applications directory if it doesn't exist
    if (!(Test-Path $ApplicationsDir)) {
        New-Item -ItemType Directory -Path $ApplicationsDir -Force | Out-Null
        Write-Log "Created Applications directory at $ApplicationsDir"
    } else {
        Write-Log "Applications directory already present at $ApplicationsDir"
    }
    $ScoopDir = Join-Path $ApplicationsDir "Scoop"

    # Check if Scoop is already installed by running the command
    $ScoopInstalled = $false
    try {
        $output = & scoop --version 2>$null
        if ($output) {
            $ScoopInstalled = $true
        }
    } catch {
        $ScoopInstalled = $false
    }

    Update-Ui -Progress 15 -Message "Checking for system-wide Scoop installation"
    if ($ScoopInstalled) {
        Update-Ui -Progress 100 -Message "Scoop is already installed."
        Start-Sleep -Seconds 1
        Update-Ui -Progress 0 -Message "Starting Python installation"
    } else {
        Update-Ui -Progress 50 -Message "Installing Scoop"
        Write-Log "Running Scoop installer at $ScoopDir"
        irm get.scoop.sh -outfile 'scoop_installer.ps1'
        Invoke-UiPump
        .\scoop_installer.ps1 -ScoopDir $ScoopDir -ScoopGlobalDir 'C:\GlobalScoopApps' -RunAsAdmin
        Update-Ui -Progress 100 -Message "Scoop installed successfully."
        Start-Sleep -Seconds 3
        Update-Ui -Progress 0 -Message "Starting Python installation"
    }

    # Ensure Git is available for Scoop buckets
    $GitInstalled = $false
    try {
        $gitOutput = & git --version 2>$null
        if ($gitOutput) {
            $GitInstalled = $true
        }
    } catch {
        $GitInstalled = $false
    }

    if (-not $GitInstalled) {
        Update-Ui -Progress 5 -Message "Installing Git with Scoop"
        Invoke-UiPump
        & scoop install git
        Write-Log "Git installation finished with exit code $LASTEXITCODE."
        Start-Sleep -Seconds 1
    } else {
        Write-Log "Git already available for Scoop buckets."
    }

    Update-Ui -Progress 10 -Message "Checking Python installation"
    $PythonInstalled = $false
    $PythonExePath = $null
    [version]$PythonVersion = $null
    try {
        $output = & python --version 2>$null
        if ($output) {
            if ($output -match '(\d+\.\d+\.\d+)') {
                $PythonVersion = [version]$Matches[1]
            }
            $PythonInstalled = $true
            $PythonExePath = (Get-Command python).Source
        }
    } catch {
        $PythonInstalled = $false
    }

    if ($PythonInstalled -and $PythonVersion) {
        Write-Log "Detected Python $PythonVersion at $PythonExePath"
    }
    if ($PythonInstalled -and $PythonVersion -and ($PythonVersion -lt [version]"3.9" -or $PythonVersion -ge [version]"3.13")) {
        Update-Ui -Progress 20 -Message "Detected Python $PythonVersion incompatible. Installing Python 3.12"
        Start-Sleep -Seconds 1
        $PythonInstalled = $false
        $PythonExePath = $null
    }

    if ($PythonInstalled) {
        Update-Ui -Progress 100 -Message "Python is already installed."
        Start-Sleep -Seconds 2
        [System.Windows.Forms.MessageBox]::Show("Python ist bereits installiert.", "Installation Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } else {
        Update-Ui -Progress 40 -Message "Installing Python 3.12 with Scoop"
        $bucketList = & scoop bucket list 2>$null
        if (-not ($bucketList -match 'versions')) {
            Write-Log "Adding Scoop 'versions' bucket."
            & scoop bucket add versions | Out-Null
        }
        & scoop install python312
        Write-Log "Python 3.12 installation finished with exit code $LASTEXITCODE."

        $PythonPrefix = (& scoop prefix python312 2>$null).Trim()
        if (-not $PythonPrefix) {
            Write-Log "Unable to determine Scoop prefix for python312."
            throw "Unable to determine Scoop prefix for python312."
        }
        Write-Log "Determined Scoop prefix for python312: $PythonPrefix"

        $PythonExePath = Join-Path $PythonPrefix "python.exe"
        $PythonDirPath = Split-Path $PythonExePath
        Write-Log "Python executable resolved at $PythonExePath"

        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            [Environment]::SetEnvironmentVariable("PATH", $PythonDirPath, "User")
            Write-Log "User PATH initialised with $PythonDirPath"
        } elseif (-not (($userPath -split ';') -contains $PythonDirPath)) {
            [Environment]::SetEnvironmentVariable("PATH", $userPath.TrimEnd(';') + ';' + $PythonDirPath, "User")
            Write-Log "User PATH augmented with $PythonDirPath"
        }
        if (-not (($env:PATH -split ';') -contains $PythonDirPath)) {
            $env:PATH = "$env:PATH;$PythonDirPath"
            Write-Log "Session PATH augmented with $PythonDirPath"
        }

        Update-Ui -Progress 70 -Message "Registering Python with Windows"
        $Pep514RegPath = Join-Path $PythonPrefix "install-pep-514.reg"
        try {
            if (Test-Path $Pep514RegPath) {
                Start-Process -FilePath reg.exe -ArgumentList "import `"$Pep514RegPath`"" -Wait -NoNewWindow
                Write-Log "PEP 514 registration imported from $Pep514RegPath"
            } else {
                Write-Warning "PEP 514 registration file not found at $Pep514RegPath."
                Write-Log "PEP 514 registration file not found at $Pep514RegPath."
            }
        } catch {
            Write-Warning "Failed to register Python: $($_.Exception.Message)"
            Write-Log "Failed to register Python: $($_.Exception.Message)"
        }

        Update-Ui -Progress 80 -Message "Cleaning up before PyQt installation"
        Start-Sleep -Seconds 2
    }

    # Create Modules directory (for both cases)
    $ModulesDir = Join-Path $ApplicationsDir "Modules"
    if (!(Test-Path $ModulesDir)) {
        New-Item -ItemType Directory -Path $ModulesDir -Force | Out-Null
        Write-Log "Created Modules directory at $ModulesDir"
    } else {
        Write-Log "Modules directory already present at $ModulesDir"
    }

    # Create PyQt directory
    $PyQtDir = Join-Path $ModulesDir "PyQt"
    if (!(Test-Path $PyQtDir)) {
        New-Item -ItemType Directory -Path $PyQtDir -Force | Out-Null
        Write-Log "Created PyQt directory at $PyQtDir"
    } else {
        Write-Log "PyQt directory already present at $PyQtDir"
    }

    Update-Ui -Progress 85 -Message "Installing PyQt/PySide6..."
    Invoke-UiPump
    & $PythonExePath -m pip install --upgrade pip
    Write-Log "pip upgraded via $PythonExePath"
    & $PythonExePath -m pip install PySide6 --target $PyQtDir
    Write-Log "PySide6 installed into $PyQtDir"

    Update-Ui -Progress 100 -Message "Installation completed." -Command "StopMusic"
    Start-Sleep -Seconds 2

    # ensure UI stopped and disposed
    Stop-InstallUI
    Write-Log "Installation UI closed."
} else {
    Write-Log "Script not executed as administrator. Showing warning dialog."
    [System.Windows.Forms.MessageBox]::Show("Der Script wird nicht als Administrator ausgeführt. Es wird geschlossen.", "Admin Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
}

Write-Log "Awaiting final exit confirmation."
Read-Host "Press Enter to exit"
Write-Log "----- Installer run finished -----"