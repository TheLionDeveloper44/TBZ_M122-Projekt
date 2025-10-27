# Check if running as administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Load Windows Forms assembly
Add-Type -AssemblyName System.Windows.Forms

if ($IsAdmin) {
    # Create loading screen form
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Python Installation Progress"
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

    # Update progress: Checking for system-wide Python
    $ProgressBar.Value = 5
    $StatusLabel.Text = "Checking for system-wide Python..."
    $Form.Refresh()

    # Check if Python is already installed system-wide
    try {
        $pythonVersion = & py --version 2>$null
        if ($pythonVersion -match "Python") {
            $ProgressBar.Value = 100
            $StatusLabel.Text = "Python is already installed system-wide."
            $Form.Refresh()
            Start-Sleep -Seconds 2
            $Form.Close()
            [System.Windows.Forms.MessageBox]::Show("Python ist bereits systemweit installiert. Installation abgebrochen.", "Python Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            exit
        }
    } catch {
        # Python not found system-wide, proceed
    }

    # Get the script directory and set paths
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ParentDir = Split-Path -Parent $ScriptDir
    $ApplicationsDir = Join-Path $ParentDir "Applications"
    $PythonDir = Join-Path $ApplicationsDir "Python"

    # Create Applications directory if it doesn't exist
    if (!(Test-Path $ApplicationsDir)) {
        New-Item -ItemType Directory -Path $ApplicationsDir -Force
    }

    # Update progress: Checking Python installation
    $ProgressBar.Value = 15
    $StatusLabel.Text = "Checking Python installation..."
    $Form.Refresh()

    # Check if Python is already installed in the target directory
    $PythonExePath = Join-Path $PythonDir "python.exe"
    if (Test-Path $PythonExePath) {
        $ProgressBar.Value = 100
        $StatusLabel.Text = "Python is already installed."
        $Form.Refresh()
        Start-Sleep -Seconds 2  # Brief pause to show completion
        $Form.Close()
        [System.Windows.Forms.MessageBox]::Show("Python ist bereits installiert.", "Installation Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } else {
        # Create Python directory if it doesn't exist
        if (!(Test-Path $PythonDir)) {
            New-Item -ItemType Directory -Path $PythonDir -Force
        }

        # Update progress: Downloading Python
        $ProgressBar.Value = 40
        $StatusLabel.Text = "Downloading Python..."
        $Form.Refresh()

        # Download the latest Python installer (assuming 64-bit Windows)
        $PythonUrl = "https://www.python.org/ftp/python/3.11.5/python-3.11.5-amd64.exe"  # Update to latest version as needed
        $InstallerPath = Join-Path $env:TEMP "python-installer.exe"
        Invoke-WebRequest -Uri $PythonUrl -OutFile $InstallerPath

        # Update progress: Installing Python
        $ProgressBar.Value = 60
        $StatusLabel.Text = "Installing Python..."
        $Form.Refresh()

        # Install Python silently to the specified directory
        Start-Process -FilePath $InstallerPath -ArgumentList "/quiet InstallAllUsers=0 Include_launcher=0 Include_test=0 SimpleInstall=1 TargetDir=`"$PythonDir`"" -Wait

        # Update progress: Cleaning up
        $ProgressBar.Value = 80
        $StatusLabel.Text = "Cleaning up..."
        $Form.Refresh()

        # Clean up installer
        Remove-Item $InstallerPath

        # Update progress: Completed
        $ProgressBar.Value = 100
        $StatusLabel.Text = "Installation completed."
        $Form.Refresh()
        Start-Sleep -Seconds 2  # Brief pause to show completion
        $Form.Close()
    }
} else {
    [System.Windows.Forms.MessageBox]::Show("Der Script wird nicht als Administrator ausgeführt. Es wird geschlossen.", "Admin Check", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
}