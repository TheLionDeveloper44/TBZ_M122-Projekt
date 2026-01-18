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
$script:ScoopCmdPath = $null
$script:ScoopInstallDir = $null
$script:ScoopGlobalDir = 'C:\GlobalScoopApps'
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
function Show-FatalError {
    param([string]$Message)
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-Log ("FATAL: {0}" -f $Message)
    }
    try { Stop-InstallUI } catch {}
    [System.Windows.Forms.MessageBox]::Show($Message, "Installation failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
function Resolve-ScoopExecutable {
    param([string]$InstallDir)
    $candidates = @(
        (Join-Path $InstallDir "shims\scoop.cmd"),
        (Join-Path $InstallDir "shims\scoop.ps1"),
        (Join-Path $env:USERPROFILE "scoop\shims\scoop.cmd"),
        (Join-Path $env:USERPROFILE "scoop\shims\scoop.ps1"),
        (Get-Command scoop -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
    ) | Where-Object { $_ -and (Test-Path $_) }
    return $candidates | Select-Object -First 1
}
function Invoke-ScoopCommand {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$Description = "Scoop operation",
        [int]$TimeoutSeconds = 300,
        [switch]$CaptureOutput,
        [string]$ScoopPath,
        [string]$ScoopRoot,
        [string]$ScoopGlobalRoot
    )
    if (-not $ScoopPath) { $ScoopPath = $script:ScoopCmdPath }
    if (-not $ScoopPath) { $ScoopPath = Resolve-ScoopExecutable -InstallDir $script:ScoopInstallDir }
    if (-not $ScoopPath) {
        $msg = "Scoop executable not found for: $Description"
        Write-Log $msg
        throw $msg
    }
    if (-not $ScoopRoot) { $ScoopRoot = $script:ScoopInstallDir }
    if (-not $ScoopGlobalRoot) { $ScoopGlobalRoot = $script:ScoopGlobalDir }
    $script:ScoopCmdPath = $ScoopPath
    Write-Log ("{0} started (timeout {1}s): {2} {3}" -f $Description, $TimeoutSeconds, $ScoopPath, ($Arguments -join ' '))
    $job = Start-Job -ScriptBlock {
        param($ArgsList, $ScoopExe, $ScoopRootInner, $ScoopGlobalInner)
        if ($ScoopRootInner) { $env:SCOOP = $ScoopRootInner }
        if ($ScoopGlobalInner) { $env:SCOOP_GLOBAL = $ScoopGlobalInner }
        $output = & $ScoopExe @ArgsList 2>&1
        [pscustomobject]@{
            Output   = $output
            ExitCode = $LASTEXITCODE
        }
    } -ArgumentList (,($Arguments), $ScoopPath, $ScoopRoot, $ScoopGlobalRoot)
    try {
        if (-not (Wait-Job -Job $job -Timeout $TimeoutSeconds)) {
            Stop-Job $job -Force | Out-Null
            $msg = "{0} exceeded timeout of {1} seconds." -f $Description, $TimeoutSeconds
            Write-Log $msg
            throw $msg
        }
        $result = Receive-Job $job
    } finally {
        if ($job) { Remove-Job $job -Force -ErrorAction SilentlyContinue }
    }
    if (-not $result -or $result.ExitCode -ne 0) {
        if ($result -and $result.Output) {
            $result.Output | ForEach-Object { Write-Log ("[scoop] {0}" -f $_) }
        } else {
            Write-Log "[scoop] No output captured from Scoop."
        }
        $code = if ($result) { $result.ExitCode } else { 'unknown' }
        $outputText = ''
        if ($result -and $result.Output) {
            $outputText = "`nOutput:`n" + ($result.Output -join [Environment]::NewLine)
        } else {
            $outputText = "`nNo output captured from Scoop. Check Scoop logs under $ScoopRoot or `$env:USERPROFILE\scoop\logs."
        }
        $msg = "{0} failed with exit code {1}.{2}" -f $Description, $code, $outputText
        Write-Log $msg
        throw $msg
    }
    Write-Log ("Completed {0}." -f $Description)
    if ($CaptureOutput) { return $result.Output }
}

# Load UI module (separated UI code)
. "$ScriptDir\ui_runner-installer.ps1"

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
function Get-FirstExistingPath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }
    return $null
}
function Set-PythonFileAssociations {
    param(
        [Parameter(Mandatory)][string]$PyLauncherPath,
        [Parameter(Mandatory)][string]$PywLauncherPath
    )
    if (-not (Test-Path $PyLauncherPath)) { throw "py.exe not found at $PyLauncherPath" }
    if (-not (Test-Path $PywLauncherPath)) { throw "pyw.exe not found at $PywLauncherPath" }
    Write-Log "Configuring .py association to $PyLauncherPath"
    & cmd.exe /c "assoc .py=Python.File" | Out-Null
    & cmd.exe /c ("ftype Python.File=`"{0}`" `"%1`" %*" -f $PyLauncherPath) | Out-Null
    Write-Log "Configuring .pyw association to $PywLauncherPath"
    & cmd.exe /c "assoc .pyw=Python.NoConFile" | Out-Null
    & cmd.exe /c ("ftype Python.NoConFile=`"{0}`" `"%1`" %*" -f $PywLauncherPath) | Out-Null
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
    try {
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
        $script:ScoopInstallDir = $ScoopDir
        $script:ScoopGlobalDir = 'C:\GlobalScoopApps'
        $ScoopCmdPath = Resolve-ScoopExecutable -InstallDir $ScoopDir

        # Check if Scoop is already installed by running the command
        $ScoopInstalled = $false
        try {
            $versionOutput = Invoke-ScoopCommand -Arguments @('--version') -Description "Checking Scoop version" -CaptureOutput
            if ($versionOutput) { $ScoopInstalled = $true }
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
            .\scoop_installer.ps1 -ScoopDir $ScoopDir -ScoopGlobalDir $script:ScoopGlobalDir -RunAsAdmin
            Update-Ui -Progress 100 -Message "Scoop installed successfully."
            Start-Sleep -Seconds 3
            Update-Ui -Progress 0 -Message "Starting Python installation"
            $ScoopCmdPath = Resolve-ScoopExecutable -InstallDir $ScoopDir
            $ScoopShimsDir = Join-Path $ScoopDir "shims"
            if (-not (($env:PATH -split ';') -contains $ScoopShimsDir) -and (Test-Path $ScoopShimsDir)) {
                $env:PATH = "$env:PATH;$ScoopShimsDir"
                Write-Log "Session PATH augmented with $ScoopShimsDir"
            }
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
            try {
                Invoke-ScoopCommand -Arguments @('install','git') -Description "Installing Git with Scoop" -ScoopPath $ScoopCmdPath -ScoopRoot $script:ScoopInstallDir -ScoopGlobalRoot $script:ScoopGlobalDir
                Write-Log "Git installation completed."
            } catch {
                Show-FatalError -Message ("Git installation failed: {0}" -f $_.Exception.Message)
            }
            Start-Sleep -Seconds 1
        } else {
            Write-Log "Git already available for Scoop buckets."
        }

        Update-Ui -Progress 10 -Message "Checking Python installation"
        $PythonInstalled = $false
        $PythonExePath = $null
        $PythonwExePath = $null
        [version]$PythonVersion = $null
        try {
            $output = & python --version 2>$null
            if ($output) {
                if ($output -match '(\d+\.\d+\.\d+)') {
                    $PythonVersion = [version]$Matches[1]
                }
                $PythonInstalled = $true
                $PythonExePath = (Get-Command python).Source
                $PythonDirPath = Split-Path $PythonExePath
                $PythonwExePath = Join-Path $PythonDirPath 'pythonw.exe'
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
            $bucketListOutput = Invoke-ScoopCommand -Arguments @('bucket','list') -Description "Listing Scoop buckets" -CaptureOutput -ScoopPath $ScoopCmdPath -ScoopRoot $script:ScoopInstallDir -ScoopGlobalRoot $script:ScoopGlobalDir
            $bucketListText = ($bucketListOutput -join [Environment]::NewLine)
            if (-not ($bucketListText -match 'versions')) {
                Write-Log "Adding Scoop 'versions' bucket."
                Invoke-ScoopCommand -Arguments @('bucket','add','versions') -Description "Adding Scoop 'versions' bucket" -ScoopPath $ScoopCmdPath -ScoopRoot $script:ScoopInstallDir -ScoopGlobalRoot $script:ScoopGlobalDir
            }
            Invoke-ScoopCommand -Arguments @('install','python312') -Description "Installing Python 3.12 via Scoop" -ScoopPath $ScoopCmdPath -ScoopRoot $script:ScoopInstallDir -ScoopGlobalRoot $script:ScoopGlobalDir
            Write-Log "Python 3.12 installation completed."
            $pythonPrefixOutput = Invoke-ScoopCommand -Arguments @('prefix','python312') -Description "Resolving python312 prefix" -CaptureOutput -ScoopPath $ScoopCmdPath -ScoopRoot $script:ScoopInstallDir -ScoopGlobalRoot $script:ScoopGlobalDir
            $PythonPrefix = ($pythonPrefixOutput | Select-Object -Last 1).Trim()
            if (-not $PythonPrefix) {
                Write-Log "Unable to determine Scoop prefix for python312."
                throw "Unable to determine Scoop prefix for python312."
            }
            Write-Log "Determined Scoop prefix for python312: $PythonPrefix"

            $PythonExePath = Join-Path $PythonPrefix "python.exe"
            $PythonDirPath = Split-Path $PythonExePath
            $PythonwExePath = Join-Path $PythonPrefix "pythonw.exe"
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

        Update-Ui -Progress 85 -Message "Installing PySide6"
        Invoke-UiPump
        & $PythonExePath -m pip install --upgrade pip
        Write-Log "pip upgraded via $PythonExePath"
        & $PythonExePath -m pip install PySide6
        Write-Log "PySide6 installed globally via pip"

        Update-Ui -Progress 90 -Message "Configuring Python file associations"
        Invoke-UiPump
        try {
            $PyLauncherCandidates = @()
            $pyCmd = Get-Command py.exe -ErrorAction SilentlyContinue
            if ($pyCmd) { $PyLauncherCandidates += $pyCmd.Source }
            $PyLauncherCandidates += (Join-Path $env:WINDIR 'py.exe')
            if ($PythonDirPath) { $PyLauncherCandidates += (Join-Path $PythonDirPath 'py.exe') }
            $PyLauncherPath = Get-FirstExistingPath -Candidates $PyLauncherCandidates
            if (-not $PyLauncherPath -and $PythonExePath) {
                $PyLauncherPath = Join-Path $PythonDirPath 'py.exe'
                Copy-Item -Path $PythonExePath -Destination $PyLauncherPath -Force
                Write-Log "py.exe shim created at $PyLauncherPath"
            }

            $PywLauncherCandidates = @()
            $pywCmd = Get-Command pyw.exe -ErrorAction SilentlyContinue
            if ($pywCmd) { $PywLauncherCandidates += $pywCmd.Source }
            $PywLauncherCandidates += (Join-Path $env:WINDIR 'pyw.exe')
            if ($PythonDirPath) { $PywLauncherCandidates += (Join-Path $PythonDirPath 'pyw.exe') }
            $PywLauncherPath = Get-FirstExistingPath -Candidates $PywLauncherCandidates
            if (-not $PywLauncherPath -and $PythonwExePath -and (Test-Path $PythonwExePath)) {
                $PywLauncherPath = Join-Path $PythonDirPath 'pyw.exe'
                Copy-Item -Path $PythonwExePath -Destination $PywLauncherPath -Force
                Write-Log "pyw.exe shim created at $PywLauncherPath"
            }

            if (-not (Test-Path $PyLauncherPath)) { throw "py.exe launcher not found." }
            if (-not (Test-Path $PywLauncherPath)) { throw "pyw.exe launcher not found." }

            Set-PythonFileAssociations -PyLauncherPath $PyLauncherPath -PywLauncherPath $PywLauncherPath
        } catch {
            Show-FatalError -Message ("Failed to configure Python file associations: {0}" -f $_.Exception.Message)
        }

        Update-Ui -Progress 100 -Message "Installation completed." -Command "StopMusic"
        Start-Sleep -Seconds 2

        # ensure UI stopped and disposed
        Stop-InstallUI
        Write-Log "Installation UI closed."
    } catch {
        Show-FatalError -Message ("Unhandled error: {0}" -f $_.Exception.Message)
    }
} else {
    Write-Log "Script not executed as administrator. Showing warning dialog."
    [System.Windows.Forms.MessageBox]::Show("Der Script wird nicht als Administrator ausgeführt. Es wird geschlossen.", "Admin Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
}

Write-Log "Awaiting final exit confirmation."
Read-Host "Press Enter to exit"
Write-Log "----- Installer run finished -----"