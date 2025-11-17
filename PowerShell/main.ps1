# Check if running as administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Load Windows Forms assembly
Add-Type -AssemblyName System.Windows.Forms

# Check Internet availability
$InternetTestUri = "https://www.google.com"
$InternetAvailable = $true
try {
    $request = [System.Net.WebRequest]::Create($InternetTestUri)
    $request.Method = "HEAD"
    $request.Timeout = 5000
    $response = $request.GetResponse()
    $response.Close()
} catch {
    $InternetAvailable = $false
}
if (-not $InternetAvailable) {
    [System.Windows.Forms.MessageBox]::Show("Keine Internetverbindung. Installation wird beendet.", "Internet Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

if ($IsAdmin) {
    # Create loading screen form
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Installation Progress"
    $Form.Size = New-Object System.Drawing.Size(400, 150)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog"
    $Form.ControlBox = $false  # Disable close button

    $ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $ProgressBar.Location = New-Object System.Drawing.Point(20, 50)
    $ProgressBar.Size = New-Object System.Drawing.Size(350, 20)
    $ProgressBar.Minimum = 0
    $ProgressBar.Maximum = 100
    $Form.Controls.Add($ProgressBar)

    $StatusLabel = New-Object System.Windows.Forms.Label
    $StatusLabel.Location = New-Object System.Drawing.Point(20, 20)
    $StatusLabel.Size = New-Object System.Drawing.Size(350, 20)
    $StatusLabel.Text = "Starting..."
    $Form.Controls.Add($StatusLabel)

    $Form.Show()
    $Form.Refresh()

    # Update progress: Checking for system-wide Scoop installation
    $ProgressBar.Value = 15
    $StatusLabel.Text = "Checking for system-wide Scoop installation..."
    $Form.Refresh()

    # Get the script directory and set paths
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ParentDir = Split-Path -Parent $ScriptDir
    $ApplicationsDir = Join-Path $ParentDir "Applications"
    $PythonDir = Join-Path $ApplicationsDir "Python"

    # Create Applications directory if it doesn't exist
    if (!(Test-Path $ApplicationsDir)) {
        New-Item -ItemType Directory -Path $ApplicationsDir -Force
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

    if ($ScoopInstalled) {
        # Scoop is already installed
        $ProgressBar.Value = 100
        $StatusLabel.Text = "Scoop is already installed."
        $Form.Refresh()
        Start-Sleep -Seconds 1
        $ProgressBar.Value = 0
        $StatusLabel.Text = "Starting Python installation..."
        $Form.Refresh()
    } else {
        # Update progress: Installing Scoop
        $ProgressBar.Value = 50
        $StatusLabel.Text = "Installing Scoop..."
        $Form.Refresh()
        Start-Sleep -Seconds 3

        # Install Scoop
        irm get.scoop.sh -outfile 'scoop_installer.ps1'
        .\scoop_installer.ps1 -ScoopDir $ScoopDir -ScoopGlobalDir 'C:\GlobalScoopApps' -RunAsAdmin

        # Set progress to 100% after Scoop installation with a brief pause, then reset to 0% for Python phase
        $ProgressBar.Value = 100
        $StatusLabel.Text = "Scoop installed successfully."
        $Form.Refresh()
        Start-Sleep -Seconds 3
        $ProgressBar.Value = 0
        $StatusLabel.Text = "Starting Python installation..."
        $Form.Refresh()
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
        $ProgressBar.Value = 5
        $StatusLabel.Text = "Installing Git with Scoop..."
        $Form.Refresh()
        & scoop install git
        Start-Sleep -Seconds 1
    }

    # Update progress: Checking Python installation (reset scale)
    $ProgressBar.Value = 10
    $StatusLabel.Text = "Checking Python installation..."
    $Form.Refresh()

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

    if ($PythonInstalled -and $PythonVersion -and ($PythonVersion -lt [version]"3.9" -or $PythonVersion -ge [version]"3.13")) {
        $ProgressBar.Value = 20
        $StatusLabel.Text = "Detected Python $PythonVersion incompatible. Installing Python 3.12..."
        $Form.Refresh()
        Start-Sleep -Seconds 1
        $PythonInstalled = $false
        $PythonExePath = $null
    }

    if ($PythonInstalled) {
        $ProgressBar.Value = 100
        $StatusLabel.Text = "Python is already installed."
        $Form.Refresh()
        Start-Sleep -Seconds 2
        [System.Windows.Forms.MessageBox]::Show("Python ist bereits installiert.", "Installation Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } else {
        $ProgressBar.Value = 40
        $StatusLabel.Text = "Installing Python 3.12 with Scoop..."
        $Form.Refresh()

        $bucketList = & scoop bucket list 2>$null
        if (-not ($bucketList -match 'versions')) {
            & scoop bucket add versions | Out-Null
        }

        & scoop install python312

        $PythonPrefix = (& scoop prefix python312 2>$null).Trim()
        if (-not $PythonPrefix) {
            throw "Unable to determine Scoop prefix for python312."
        }

        $PythonExePath = Join-Path $PythonPrefix "python.exe"
        $PythonDirPath = Split-Path $PythonExePath

        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            [Environment]::SetEnvironmentVariable("PATH", $PythonDirPath, "User")
        } elseif (-not (($userPath -split ';') -contains $PythonDirPath)) {
            [Environment]::SetEnvironmentVariable("PATH", $userPath.TrimEnd(';') + ';' + $PythonDirPath, "User")
        }
        if (-not (($env:PATH -split ';') -contains $PythonDirPath)) {
            $env:PATH = "$env:PATH;$PythonDirPath"
        }

        $ProgressBar.Value = 70
        $StatusLabel.Text = "Registering Python with Windows..."
        $Form.Refresh()

        $Pep514RegPath = Join-Path $PythonPrefix "install-pep-514.reg"
        try {
            if (Test-Path $Pep514RegPath) {
                Start-Process -FilePath reg.exe -ArgumentList "import `"$Pep514RegPath`"" -Wait -NoNewWindow
            } else {
                Write-Warning "PEP 514 registration file not found at $Pep514RegPath."
            }
        } catch {
            Write-Warning "Failed to register Python: $($_.Exception.Message)"
        }

        $ProgressBar.Value = 80
        $StatusLabel.Text = "Cleaning up..."
        $Form.Refresh()
        Read-Host "Press Enter to continue with PyQt installation"
    }

    # Create Modules directory (for both cases)
    $ModulesDir = Join-Path $ApplicationsDir "Modules"
    if (!(Test-Path $ModulesDir)) {
        New-Item -ItemType Directory -Path $ModulesDir -Force
    }

    # Create PyQt directory
    $PyQtDir = Join-Path $ModulesDir "PyQt"
    if (!(Test-Path $PyQtDir)) {
        New-Item -ItemType Directory -Path $PyQtDir -Force
    }

    # Update progress: Installing PyQt/PySide6 (for already installed case)
    $ProgressBar.Value = 85
    $StatusLabel.Text = "Installing PyQt/PySide6..."
    $Form.Refresh()

    # Upgrade pip and install PySide6 into PyQt directory
    & $PythonExePath -m pip install --upgrade pip
    & $PythonExePath -m pip install PySide6 --target $PyQtDir

    # Update progress: Completed
    $ProgressBar.Value = 100
    $StatusLabel.Text = "Installation completed."
    $Form.Refresh()
    Start-Sleep -Seconds 2  # Brief pause to show completion
    $Form.Close()
} else {
    [System.Windows.Forms.MessageBox]::Show("Der Script wird nicht als Administrator ausgeführt. Es wird geschlossen.", "Admin Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
}

# Pause to allow viewing of error messages
Read-Host "Press Enter to exit"