# Author: TheLionDeveloper44
# Dieses Skript unterliegt der Lizenz, die in der LICENSE-Datei im Stammverzeichnis dieses Repositories enthalten ist.
# Ohne ausdrückliche schriftliche Genehmigung ist es untersagt, dieses Skript zu kopieren, zu modifizieren oder zu verbreiten.

# Dieses Skript implementiert eine einfache UI-Schleife für Installationsprozesse.
# Es muss umgehend mit main.ps1 ausgeführt werden.

if (-not $script:UiModulePath) {
    $script:UiModulePath = $PSCommandPath
}
$script:UiHost = $null
$script:UiState = $null

function Invoke-UiPump { return }

function Start-InstallUI {
    param([string]$Title = "Installer")
    if ($script:UiHost) { return }
    $queue = [System.Collections.Concurrent.ConcurrentQueue[System.Collections.Hashtable]]::new()
    $script:UiHost = @{
        Queue = $queue
        Title = $Title
    }
    try {
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
        $threadOptionsType = [type]::GetType("System.Threading.ThreadOptions", $false)
        if ($threadOptionsType) {
            $runspace.ThreadOptions = [Enum]::Parse($threadOptionsType, "ReuseThread")
        }
        $runspace.Open()
        $runspace.SessionStateProxy.SetVariable("UiQueue", $queue)
        $runspace.SessionStateProxy.SetVariable("UiTitle", $Title)
        $runspace.SessionStateProxy.SetVariable("UiRunnerPath", $script:UiModulePath)

        $ps = [PowerShell]::Create()
        $ps.Runspace = $runspace
        $ps.AddScript({
            . $UiRunnerPath
            Start-UiCore -Queue $UiQueue -Title $UiTitle
        }) | Out-Null

        $async = $ps.BeginInvoke()
        $script:UiHost.Runspace = $runspace
        $script:UiHost.PowerShell = $ps
        $script:UiHost.AsyncResult = $async
    } catch {
        Stop-InstallUI
        throw
    }
}

function Update-Ui {
    param(
        [int]$Progress = -1,
        [string]$Message
    )
    if ($Message -and (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
        Write-Log $Message
    }
    if (-not $script:UiHost -or -not $script:UiHost.Queue) { return }
    $payload = @{}
    if ($Progress -ge 0) { $payload.Progress = [int]$Progress }
    if ($Message) { $payload.Message = $Message }
    if ($payload.Count -eq 0) { return }
    $script:UiHost.Queue.Enqueue([System.Collections.Hashtable]$payload)
}

function Stop-InstallUI {
    if (-not $script:UiHost) { return }
    if ($script:UiHost.Queue) {
        $script:UiHost.Queue.Enqueue(@{ Command = 'Close' })
    }
    if ($script:UiHost.AsyncResult -and $script:UiHost.PowerShell) {
        $script:UiHost.AsyncResult.AsyncWaitHandle.WaitOne(5000) | Out-Null
        try { $script:UiHost.PowerShell.EndInvoke($script:UiHost.AsyncResult) } catch {}
    }
    if ($script:UiHost.PowerShell) { $script:UiHost.PowerShell.Dispose() }
    if ($script:UiHost.Runspace) {
        $script:UiHost.Runspace.Close()
        $script:UiHost.Runspace.Dispose()
    }
    $script:UiHost = $null
}

function Start-UiCore {
    param(
        [System.Collections.Concurrent.ConcurrentQueue[System.Collections.Hashtable]]$Queue,
        [string]$Title
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = $Title
    $Form.Size = New-Object System.Drawing.Size(640, 360)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog"
    $Form.ControlBox = $false
    $Form.TopMost = $true
    $Form.BackColor = [System.Drawing.Color]::FromArgb(24, 32, 58)
    $Form.Add_Paint({
        param($sender, $e)
        $rect = [System.Drawing.Rectangle]::FromLTRB(0, 0, $sender.Width, $sender.Height)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rect,
            [System.Drawing.Color]::FromArgb(255, 22, 33, 62),
            [System.Drawing.Color]::FromArgb(255, 46, 78, 129),
            90
        )
        $e.Graphics.FillRectangle($brush, $rect)
        $brush.Dispose()
    })
    $doubleBufferedProp = $Form.GetType().GetProperty(
        "DoubleBuffered",
        [System.Reflection.BindingFlags]([System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
    )
    if ($doubleBufferedProp) { $doubleBufferedProp.SetValue($Form, $true, $null) }

    $HeaderLabel = New-Object System.Windows.Forms.Label
    $HeaderLabel.Text = $Title
    $HeaderLabel.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $HeaderLabel.ForeColor = [System.Drawing.Color]::White
    $HeaderLabel.AutoSize = $true
    $HeaderLabel.Location = New-Object System.Drawing.Point(22, 15)
    $HeaderLabel.BackColor = [System.Drawing.Color]::Transparent
    $Form.Controls.Add($HeaderLabel)

    $SubtitleLabel = New-Object System.Windows.Forms.Label
    $SubtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $SubtitleLabel.ForeColor = [System.Drawing.Color]::Gainsboro
    $SubtitleLabel.AutoSize = $true
    $SubtitleLabel.Location = New-Object System.Drawing.Point(24, 55)
    $SubtitleLabel.BackColor = [System.Drawing.Color]::Transparent
    $Form.Controls.Add($SubtitleLabel)

    $ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $ProgressBar.Location = New-Object System.Drawing.Point(24, 210)
    $ProgressBar.Size = New-Object System.Drawing.Size(360, 26)
    $ProgressBar.Minimum = 0
    $ProgressBar.Maximum = 100
    $ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $Form.Controls.Add($ProgressBar)

    $StatusLabel = New-Object System.Windows.Forms.Label
    $StatusLabel.Location = New-Object System.Drawing.Point(50, 170)
    $StatusLabel.Size = New-Object System.Drawing.Size(340, 30)
    $StatusLabel.Text = "Starting..."
    $StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $StatusLabel.ForeColor = [System.Drawing.Color]::White
    $StatusLabel.BackColor = [System.Drawing.Color]::Transparent
    $Form.Controls.Add($StatusLabel)

    $SpinnerLabel = New-Object System.Windows.Forms.Label
    $SpinnerLabel.Location = New-Object System.Drawing.Point(24, 170)
    $SpinnerLabel.Size = New-Object System.Drawing.Size(20, 30)
    $SpinnerLabel.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
    $SpinnerLabel.ForeColor = [System.Drawing.Color]::Aqua
    $SpinnerLabel.Text = "|"
    $SpinnerLabel.BackColor = [System.Drawing.Color]::Transparent
    $Form.Controls.Add($SpinnerLabel)

    $ActionHeadingLabel = New-Object System.Windows.Forms.Label
    $ActionHeadingLabel.Text = "Action history"
    $ActionHeadingLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $ActionHeadingLabel.ForeColor = [System.Drawing.Color]::White
    $ActionHeadingLabel.AutoSize = $true
    $ActionHeadingLabel.Location = New-Object System.Drawing.Point(400, 55)
    $ActionHeadingLabel.BackColor = [System.Drawing.Color]::Transparent
    $Form.Controls.Add($ActionHeadingLabel)

    $ActionListBox = New-Object System.Windows.Forms.ListBox
    $ActionListBox.Location = New-Object System.Drawing.Point(400, 80)
    $ActionListBox.Size = New-Object System.Drawing.Size(220, 240)
    $ActionListBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $ActionListBox.BackColor = [System.Drawing.Color]::FromArgb(34, 45, 72)
    $ActionListBox.ForeColor = [System.Drawing.Color]::FromArgb(230, 245, 255)
    $ActionListBox.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Regular)
    $ActionListBox.SelectionMode = [System.Windows.Forms.SelectionMode]::None
    $ActionListBox.IntegralHeight = $false
    $ActionListBox.TabStop = $false
    $ActionListBox.HorizontalScrollbar = $true
    $Form.Controls.Add($ActionListBox)

    $SubtitleQuotes = @(
        "Lehnen Sie sich zurück, während wir die Magie entfalten..."
        "Wir richten Ihren Computer mit höchster Präzision ein."
        "Ein Augenblick Geduld, wir kümmern uns um die Details."
        "Ihre Tools werden vorbereitet, bitte entspannen Sie sich."
        "InstallCraft liefert gleich die perfekte Erfahrung."
    )
    $SubtitleIndex = 0
    $SubtitleLabel.Text = $SubtitleQuotes[$SubtitleIndex]

    $script:UiState = @{
        CurrentStatus = $StatusLabel.Text
        SpinnerIndex = 0
        DotCount = 0
        SubtitleIndex = $SubtitleIndex
        GlowValue = 180
        PulseDirection = 1
        DotElapsedMs = 0
        QuoteElapsedMs = 0
    }

    $SpinnerStates = @('|','/','-','\')
    $ActionHistoryLimit = 200
    $closing = $false

    $AnimationTimer = New-Object System.Windows.Forms.Timer
    $AnimationTimer.Interval = 250
    $AnimationTimer.Add_Tick({
        $state = $script:UiState
        if (-not $state) { return }

        $state.DotElapsedMs += $AnimationTimer.Interval
        if ($state.DotElapsedMs -ge 1000 -and $StatusLabel) {
            $state.DotElapsedMs = 0
            $state.DotCount = ($state.DotCount + 1) % 4
            $StatusLabel.Text = $state.CurrentStatus + ('.' * $state.DotCount)
        } elseif ($StatusLabel) {
            $StatusLabel.Text = $state.CurrentStatus + ('.' * $state.DotCount)
        }

        if ($SpinnerLabel) {
            $state.SpinnerIndex = ($state.SpinnerIndex + 1) % $SpinnerStates.Count
            $SpinnerLabel.Text = $SpinnerStates[$state.SpinnerIndex]
        }

        if ($HeaderLabel) {
            $state.GlowValue += 5 * $state.PulseDirection
            if ($state.GlowValue -ge 255) { $state.GlowValue = 255; $state.PulseDirection = -1 }
            elseif ($state.GlowValue -le 150) { $state.GlowValue = 150; $state.PulseDirection = 1 }
            $HeaderLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, $state.GlowValue, 230, 255)
        }

        if ($SubtitleLabel -and $SubtitleQuotes.Count -gt 0) {
            $state.QuoteElapsedMs += $AnimationTimer.Interval
            if ($state.QuoteElapsedMs -ge 10000) {
                $state.QuoteElapsedMs = 0
                $state.SubtitleIndex = ($state.SubtitleIndex + 1) % $SubtitleQuotes.Count
                $SubtitleLabel.Text = $SubtitleQuotes[$state.SubtitleIndex]
            }
        }
    })
    $AnimationTimer.Start()

    $QueueTimer = New-Object System.Windows.Forms.Timer
    $QueueTimer.Interval = 150
    $QueueTimer.Add_Tick({
        $payload = $null
        while ($Queue.TryDequeue([ref]$payload)) {
            if (-not $payload) { continue }
            if ($payload.ContainsKey('Command') -and $payload.Command -eq 'Close') {
                $closing = $true
                break
            }
            if ($payload.ContainsKey('Progress') -and $ProgressBar) {
                $value = [Math]::Max(
                    $ProgressBar.Minimum,
                    [Math]::Min([int]$payload.Progress, $ProgressBar.Maximum)
                )
                $ProgressBar.Value = $value
            }
            if ($payload.ContainsKey('Message') -and $StatusLabel) {
                $message = [string]$payload.Message
                if ($script:UiState) {
                    $script:UiState.CurrentStatus = $message
                    $script:UiState.DotCount = 0
                    $script:UiState.DotElapsedMs = 0
                }
                $StatusLabel.Text = $message
                if ($ActionListBox) {
                    $ActionListBox.Items.Insert(0, "$(Get-Date -Format 'HH:mm:ss')  $message")
                    if ($ActionListBox.Items.Count -gt $ActionHistoryLimit) {
                        $ActionListBox.Items.RemoveAt($ActionListBox.Items.Count - 1)
                    }
                }
            }
        }
        if ($closing) {
            $QueueTimer.Stop()
            if ($AnimationTimer) { $AnimationTimer.Stop() }
            $Form.Close()
        }
    })
    $QueueTimer.Start()

    $Form.Add_FormClosed({
        if ($AnimationTimer) { $AnimationTimer.Stop(); $AnimationTimer.Dispose() }
        if ($QueueTimer) { $QueueTimer.Stop(); $QueueTimer.Dispose() }
    })

    $Form.Add_Shown({ $Form.Activate() })
    [System.Windows.Forms.Application]::Run($Form)
    if ($Form -and -not $Form.IsDisposed) {
        $Form.Dispose()
    }
    $script:UiState = $null
}