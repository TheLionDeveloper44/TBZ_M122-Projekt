# Author: TheLionDeveloper44
# Dieses Skript unterliegt der Lizenz, die in der LICENSE-Datei im Stammverzeichnis dieses Repositories enthalten ist.
# Ohne ausdrückliche schriftliche Genehmigung ist es untersagt, dieses Skript zu kopieren, zu modifizieren oder zu verbreiten.

# Dieses Skript implementiert ein kompliziertes UI für Installationsprozesse.
# Dieses UI/GUI ist "völlig" Modular und kann in verschiedenen Installationsszenarien wiederverwendet werden.
# Es muss umgehend mit main.ps1 ausgeführt werden.

if (-not $script:UiModulePath) {
    $script:UiModulePath = $PSCommandPath
}
$script:UiHost = $null
$script:UiState = $null

function Invoke-UiPump { return }

function Start-InstallUI {
    param(
        [string]$Title = "Installer",
        [string]$MediaRoot
    )
    if ($script:UiHost) { return }
    $queue = [System.Collections.Concurrent.ConcurrentQueue[System.Collections.Hashtable]]::new()
    $script:UiHost = @{
        Queue = $queue
        Title = $Title
        MediaRoot = $MediaRoot
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
        $runspace.SessionStateProxy.SetVariable("UiMediaRoot", $MediaRoot)

        $ps = [PowerShell]::Create()
        $ps.Runspace = $runspace
        $ps.AddScript({
            . $UiRunnerPath
            Start-UiCore -Queue $UiQueue -Title $UiTitle -MediaRoot $UiMediaRoot
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
        [string]$Message,
        [string]$Command
    )
    if ($Message -and (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
        Write-Log $Message
    }
    if (-not $script:UiHost -or -not $script:UiHost.Queue) { return }
    $payload = @{}
    if ($Progress -ge 0) { $payload.Progress = [int]$Progress }
    if ($Message) { $payload.Message = $Message }
    if ($Command) { $payload.Command = $Command }
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
        [string]$Title,
        [string]$MediaRoot
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

    $MuteButton = New-Object System.Windows.Forms.Button
    $MuteButton.Location = New-Object System.Drawing.Point(24, 250)
    $MuteButton.Size = New-Object System.Drawing.Size(150, 32)
    $MuteButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $MuteButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 110, 160)
    $MuteButton.BackColor = [System.Drawing.Color]::FromArgb(34, 45, 72)
    $MuteButton.ForeColor = [System.Drawing.Color]::White
    $MuteButton.UseVisualStyleBackColor = $false
    $MuteButton.TabStop = $false
    $MuteButton.Text = "Mute audio"
    $Form.Controls.Add($MuteButton)

    $script:IntroOverlay = @{
        Alpha = 255
        DelayMs = 800
        Active = $true
        Panel = $null
        RequireLoop = $true
        WaitElapsedMs = 0
        MaxHoldMs = 6000
        HoldFadeStep = 12
        ReleaseFadeStep = 22
    }
    $IntroPanel = New-Object System.Windows.Forms.Panel
    $IntroPanel.Dock = 'Fill'
    $IntroPanel.Enabled = $false
    $IntroPanel.BackColor = [System.Drawing.Color]::Transparent
    $introDoubleBuffered = $IntroPanel.GetType().GetProperty(
        "DoubleBuffered",
        [System.Reflection.BindingFlags]([System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
    )
    if ($introDoubleBuffered) { $introDoubleBuffered.SetValue($IntroPanel, $true, $null) }
    $IntroPanel.Add_Paint({
        param($sender,$e)
        if (-not $script:IntroOverlay -or -not $script:IntroOverlay.Active) { return }
        $rect = $sender.ClientRectangle
        $alpha = $script:IntroOverlay.Alpha
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rect,
            [System.Drawing.Color]::FromArgb($alpha, 15, 32, 65),
            [System.Drawing.Color]::FromArgb($alpha, 60, 110, 160),
            90
        )
        $e.Graphics.FillRectangle($brush, $rect)
        $brush.Dispose()
        $titleFont = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
        $subtitleFont = New-Object System.Drawing.Font("Segoe UI", 11)
        $titleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([Math]::Min(255, $alpha + 30), 255, 255, 255))
        $subtitleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alpha, 220, 235, 255))
        $title = "InstallCraft"
        $subtitle = "Initiiert Ihre perfekte Installation"
        $titleSize = $e.Graphics.MeasureString($title, $titleFont)
        $subtitleSize = $e.Graphics.MeasureString($subtitle, $subtitleFont)
        $centerX = $rect.Width / 2
        $centerY = $rect.Height / 2
        $e.Graphics.DrawString($title, $titleFont, $titleBrush, $centerX - ($titleSize.Width / 2), $centerY - $titleSize.Height)
        $e.Graphics.DrawString($subtitle, $subtitleFont, $subtitleBrush, $centerX - ($subtitleSize.Width / 2), $centerY + 5)
        $titleBrush.Dispose(); $subtitleBrush.Dispose(); $titleFont.Dispose(); $subtitleFont.Dispose()
    })
    $Form.Controls.Add($IntroPanel)
    $IntroPanel.BringToFront()
    $script:IntroOverlay.Panel = $IntroPanel

    $script:UiAudioState = $null
    $audioTimer = $null
    $selectNextMusic = {
        if (-not $script:UiAudioState) { return $null }
        $tracks = @(Get-ChildItem -Path $script:UiAudioState.MediaRoot -Filter 'PS_Music*.wav' -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -ExpandProperty FullName)
        $script:UiAudioState.MusicTracks = $tracks
        $shouldReportPair = ($tracks.Count -eq 2 -and -not $script:UiAudioState.ReportedPair)
        if ($shouldReportPair -and (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
            $leafs = $tracks | ForEach-Object { Split-Path -Leaf $_ }
            Write-Log ("Detected 2 PS_Music tracks: {0}" -f ($leafs -join ', '))
        }
        $script:UiAudioState.ReportedPair = ($tracks.Count -eq 2)
        if ($tracks.Count -eq 0) { return $null }
        $eligible = $tracks
        if ($tracks.Count -gt 1 -and $script:UiAudioState.LastMusic) {
            $eligible = $tracks | Where-Object { $_ -ne $script:UiAudioState.LastMusic }
            if (-not $eligible -or $eligible.Count -eq 0) { $eligible = $tracks }
        }
        $selection = Get-Random -InputObject $eligible
        $script:UiAudioState.LastMusic = $selection
        return $selection
    }
    $startMusicAction = {
        if (-not $script:UiAudioState -or -not $script:UiAudioState.Controller) { return }
        $nextTrack = & $selectNextMusic
        if (-not $nextTrack) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "Unable to find any PS_Music tracks. Stopping audio playback."
            }
            & $stopAudioAction
            return
        }
        try { $script:UiAudioState.Controller.controls.stop() } catch {}
        try {
            $script:UiAudioState.Controller.settings.setMode("loop", $false)
            $script:UiAudioState.Controller.URL = $nextTrack
            $script:UiAudioState.Controller.controls.play()
            $script:UiAudioState.CurrentTrack = 'Music'
            $script:UiAudioState.LoopEngaged = $true
            $script:UiAudioState.LastPlayState = $null
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log ("Now playing {0}" -f (Split-Path -Leaf $nextTrack))
            }
        } catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log ("Failed to start {0}: {1}" -f $nextTrack, $_.Exception.Message)
            }
        }
    }
    $stopAudioAction = {
        if ($audioTimer) { $audioTimer.Stop(); $audioTimer.Dispose(); $audioTimer = $null }
        if (-not $script:UiAudioState) { return }
        if ($script:UiAudioState.Controller) {
            try { $script:UiAudioState.Controller.controls.stop() } catch {}
            try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($script:UiAudioState.Controller) | Out-Null } catch {}
            $script:UiAudioState.Controller = $null
        }
        $script:UiAudioState = $null
        if ($MuteButton) {
            $MuteButton.Enabled = $false
            $MuteButton.Text = "Audio stopped"
        }
    }

    if ($MediaRoot -and (Test-Path $MediaRoot)) {
        $introPath = Join-Path $MediaRoot "UI_Start.wav"
        $musicTracks = @(Get-ChildItem -Path $MediaRoot -Filter 'PS_Music*.wav' -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -ExpandProperty FullName)
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            switch ($musicTracks.Count) {
                0 { Write-Log "No PS_Music*.wav tracks found in $MediaRoot" }
                2 {
                    $names = $musicTracks | ForEach-Object { Split-Path -Leaf $_ }
                    Write-Log ("Detected 2 PS_Music tracks: {0}" -f ($names -join ', '))
                }
                default { Write-Log ("Detected {0} PS_Music tracks." -f $musicTracks.Count) }
            }
        }
        if ((Test-Path $introPath) -and $musicTracks.Count -gt 0) {
            try {
                $controller = New-Object -ComObject WMPlayer.OCX
                $controller.settings.volume = 75
                $controller.settings.mute = $false
                $controller.settings.setMode("loop", $false)
                $controller.URL = $introPath
                $script:UiAudioState = @{
                    Controller = $controller
                    IntroPath = $introPath
                    MusicTracks = $musicTracks
                    CurrentTrack = 'Intro'
                    IsMuted = $false
                    LoopEngaged = $false
                    MediaRoot = $MediaRoot
                    LastMusic = $null
                    ReportedPair = ($musicTracks.Count -eq 2)
                    LastPlayState = $null
                }
                $controller.controls.play()
            } catch {
                $script:UiAudioState = $null
            }
        } elseif (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "MuSoLIB assets missing in $MediaRoot"
        }
    }

    $audioTerminalStates = 0,1,8,10
    if ($script:UiAudioState) {
        $audioTimer = New-Object System.Windows.Forms.Timer
        $audioTimer.Interval = 300
        $audioTimer.Add_Tick({
            if (-not $script:UiAudioState -or -not $script:UiAudioState.Controller) { return }
            $state = $script:UiAudioState.Controller.playState
            $prev = $script:UiAudioState.LastPlayState
            if ($null -eq $prev) {
                $script:UiAudioState.LastPlayState = $state
                return
            }
            $isTerminal = $audioTerminalStates -contains $state
            $wasTerminal = $audioTerminalStates -contains $prev
            if ($isTerminal -and -not $wasTerminal -and
                $script:UiAudioState.CurrentTrack -in @('Intro','Music')) {
                & $startMusicAction
            }
            $script:UiAudioState.LastPlayState = $state
        })
        $audioTimer.Start()
    } else {
        $MuteButton.Enabled = $false
        $MuteButton.Text = "Audio unavailable"
        if ($script:IntroOverlay) { $script:IntroOverlay.RequireLoop = $false }
    }

    $MuteButton.Add_Click({
        if (-not $script:UiAudioState -or -not $script:UiAudioState.Controller) { return }
        $script:UiAudioState.IsMuted = -not $script:UiAudioState.IsMuted
        $script:UiAudioState.Controller.settings.mute = $script:UiAudioState.IsMuted
        if (-not $script:UiAudioState.IsMuted -and $script:UiAudioState.CurrentTrack -eq 'Music') {
            $script:UiAudioState.Controller.controls.play()
        }
        $MuteButton.Text = $(if ($script:UiAudioState.IsMuted) { "Unmute audio" } else { "Mute audio" })
    })
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

        if ($script:IntroOverlay -and $script:IntroOverlay.Active) {
            if ($script:IntroOverlay.DelayMs -gt 0) {
                $script:IntroOverlay.DelayMs -= $AnimationTimer.Interval
            } else {
                if ($script:IntroOverlay.RequireLoop) {
                    $script:IntroOverlay.Alpha = [Math]::Max(
                        0,
                        $script:IntroOverlay.Alpha - $script:IntroOverlay.HoldFadeStep
                    )
                    if ($script:IntroOverlay.Panel) { $script:IntroOverlay.Panel.Invalidate() }
                    $loopReady = ($script:UiAudioState -and $script:UiAudioState.LoopEngaged)
                    if ($loopReady) {
                        $script:IntroOverlay.RequireLoop = $false
                    } elseif (-not $script:UiAudioState -or
                             $script:IntroOverlay.WaitElapsedMs -ge $script:IntroOverlay.MaxHoldMs) {
                        $script:IntroOverlay.RequireLoop = $false
                    } else {
                        $script:IntroOverlay.WaitElapsedMs += $AnimationTimer.Interval
                        return
                    }
                }
                $script:IntroOverlay.Alpha = [Math]::Max(
                    0,
                    $script:IntroOverlay.Alpha - $script:IntroOverlay.ReleaseFadeStep
                )
                if ($script:IntroOverlay.Panel) { $script:IntroOverlay.Panel.Invalidate() }
                if ($script:IntroOverlay.Alpha -le 0) {
                    $script:IntroOverlay.Active = $false
                    if ($script:IntroOverlay.Panel) {
                        $script:IntroOverlay.Panel.Hide()
                        $script:IntroOverlay.Panel.Dispose()
                        $script:IntroOverlay.Panel = $null
                    }
                }
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
            if ($payload.ContainsKey('Command')) {
                switch ($payload.Command) {
                    'Close' {
                        $closing = $true
                        & $stopAudioAction
                    }
                    'StopMusic' { & $stopAudioAction }
                }
                if ($closing) { break }
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
        if ($script:IntroOverlay) {
            if ($script:IntroOverlay.Panel) { $script:IntroOverlay.Panel.Dispose() }
            $script:IntroOverlay = $null
        }
        & $stopAudioAction
    })

    $Form.Add_Shown({ $Form.Activate() })
    [System.Windows.Forms.Application]::Run($Form)
    if ($Form -and -not $Form.IsDisposed) {
        $Form.Dispose()
    }
    $script:UiState = $null
}