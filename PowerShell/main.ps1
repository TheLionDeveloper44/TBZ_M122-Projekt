# Check if running as administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Load Windows Forms assembly
Add-Type -AssemblyName System.Windows.Forms

if ($IsAdmin) {
    # Get the script directory and set paths
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ParentDir = Split-Path -Parent $ScriptDir
    $ApplicationsDir = Join-Path $ParentDir "Applications"
    $PythonDir = Join-Path $ApplicationsDir "Python"

    # Create directories if they don't exist
    if (!(Test-Path $ApplicationsDir)) {
        New-Item -ItemType Directory -Path $ApplicationsDir -Force
    }
    if (!(Test-Path $PythonDir)) {
        New-Item -ItemType Directory -Path $PythonDir -Force
    }

    # Download the latest Python installer (assuming 64-bit Windows)
    $PythonUrl = "https://www.python.org/ftp/python/3.11.5/python-3.11.5-amd64.exe"  # Update to latest version as needed
    $InstallerPath = Join-Path $env:TEMP "python-installer.exe"
    Invoke-WebRequest -Uri $PythonUrl -OutFile $InstallerPath

    # Install Python silently to the specified directory
    Start-Process -FilePath $InstallerPath -ArgumentList "/quiet InstallAllUsers=0 Include_launcher=0 Include_test=0 SimpleInstall=1 TargetDir=`"$PythonDir`"" -Wait

    # Clean up installer
    Remove-Item $InstallerPath
} else {
    [System.Windows.Forms.MessageBox]::Show("Der Script wird nicht als Administrator ausgeführt. Es wird geschlossen.", "Admin Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
}