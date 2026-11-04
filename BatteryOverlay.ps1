# Real-Time Battery Wattage, CPU Temperature & Health Overlay
# Ultra-lightweight, battery-efficient WPF overlay with System Tray ("Hidden Icons") support

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Management

# Helper unicode characters
$IconBolt    = [char]::ConvertFromUtf32(0x26A1)   # ⚡
$IconClock   = [char]::ConvertFromUtf32(0x23F1)   # ⏱
$IconPlug    = [char]::ConvertFromUtf32(0x1F50C)  # 🔌
$IconBat     = [char]::ConvertFromUtf32(0x1F50B)  # 🔋
$IconBatLow  = [char]::ConvertFromUtf32(0x1FAAB)  # 🪫
$IconTemp    = [char]::ConvertFromUtf32(0x1F321)  # 🌡

# Path configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$SettingsFile = Join-Path $ScriptDir "settings.json"

# Load settings if available
$Settings = @{
    Left = [System.Windows.SystemParameters]::PrimaryScreenWidth - 360
    Top = 30
    Compact = $false
    Opacity = 0.90
    Interval = 2
    Topmost = $true
}

if (Test-Path $SettingsFile) {
    try {
        $Loaded = Get-Content $SettingsFile -Raw | ConvertFrom-Json
        if ($Loaded.Left) { $Settings.Left = [double]$Loaded.Left }
        if ($Loaded.Top) { $Settings.Top = [double]$Loaded.Top }
        if ($null -ne $Loaded.Compact) { $Settings.Compact = [bool]$Loaded.Compact }
        if ($Loaded.Opacity) { $Settings.Opacity = [double]$Loaded.Opacity }
        if ($Loaded.Interval) { $Settings.Interval = [int]$Loaded.Interval }
        if ($null -ne $Loaded.Topmost) { $Settings.Topmost = [bool]$Loaded.Topmost }
    } catch {}
}

# Ensure position is visible within virtual screen bounds
$VirtualWidth = [System.Windows.SystemParameters]::VirtualScreenWidth
$VirtualHeight = [System.Windows.SystemParameters]::VirtualScreenHeight
if ($Settings.Left -lt 0 -or $Settings.Left -gt ($VirtualWidth - 80)) {
    $Settings.Left = [System.Windows.SystemParameters]::PrimaryScreenWidth - 360
}
if ($Settings.Top -lt 0 -or $Settings.Top -gt ($VirtualHeight - 50)) {
    $Settings.Top = 30
}

$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Battery Overlay"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        Topmost="True"
        ShowInTaskbar="False"
        ResizeMode="NoResize"
        SizeToContent="WidthAndHeight"
        WindowStartupLocation="Manual">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Segoe UI, Segoe UI Variable Display, Segoe UI Variable Text, Arial"/>
        </Style>
    </Window.Resources>
    <Border Name="MainBorder" Background="#EE16161A" BorderBrush="#33FFFFFF" BorderThickness="1" CornerRadius="16" Padding="12,6,10,6" Margin="8">
        <Border.Effect>
            <DropShadowEffect BlurRadius="12" Opacity="0.4" ShadowDepth="2" Direction="270" Color="#000000"/>
        </Border.Effect>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <!-- Power Icon & Wattage -->
            <TextBlock Name="TxtIcon" Text="&#x26A1;" FontSize="13" Foreground="#00F0FF" VerticalAlignment="Center" Margin="0,0,5,0" Cursor="SizeAll"/>
            <TextBlock Name="TxtWattage" Text="-- W" FontSize="13" FontWeight="SemiBold" Foreground="#FFFFFF" VerticalAlignment="Center" Cursor="SizeAll"/>

            <!-- Separator 1 -->
            <Rectangle Name="Sep1" Width="1" Height="14" Fill="#33FFFFFF" Margin="9,0,9,0" VerticalAlignment="Center"/>

            <!-- Battery Percentage -->
            <TextBlock Name="TxtBatteryIcon" Text="&#x1F50B;" FontSize="11" VerticalAlignment="Center" Margin="0,0,3,0" Cursor="SizeAll"/>
            <TextBlock Name="TxtPercent" Text="--%" FontSize="12.5" FontWeight="Medium" Foreground="#E2E8F0" VerticalAlignment="Center" Cursor="SizeAll"/>

            <!-- Separator 2 -->
            <Rectangle Name="Sep2" Width="1" Height="14" Fill="#33FFFFFF" Margin="9,0,9,0" VerticalAlignment="Center"/>

            <!-- CPU Temperature -->
            <TextBlock Name="TxtCpuIcon" Text="&#x1F321;" FontSize="11" Foreground="#00F0FF" VerticalAlignment="Center" Margin="0,0,3,0" Cursor="SizeAll"/>
            <TextBlock Name="TxtCpuTemp" Text="--&#x00B0;C" FontSize="12.5" FontWeight="Medium" Foreground="#E2E8F0" VerticalAlignment="Center" Cursor="SizeAll"/>

            <!-- Separator 3 -->
            <Rectangle Name="Sep3" Width="1" Height="14" Fill="#33FFFFFF" Margin="9,0,9,0" VerticalAlignment="Center"/>

            <!-- Remaining Time -->
            <TextBlock Name="TxtTimeIcon" Text="&#x23F1;" FontSize="11" Foreground="#94A3B8" VerticalAlignment="Center" Margin="0,0,3,0" Cursor="SizeAll"/>
            <TextBlock Name="TxtRemaining" Text="--:--" FontSize="12" Foreground="#CBD5E1" VerticalAlignment="Center" Cursor="SizeAll"/>

            <!-- Hide / Close Button -->
            <Button Name="BtnClose" Content="&#x2715;" Width="18" Height="18" Margin="8,0,0,0"
                    Background="Transparent" BorderThickness="0" Foreground="#64748B" FontSize="10"
                    VerticalAlignment="Center" Cursor="Hand" ToolTip="Hide to Hidden Icons Tray">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="9">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Button.Template>
            </Button>
        </StackPanel>
    </Border>
</Window>
"@

$Reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($Xaml))
$Window = [System.Windows.Markup.XamlReader]::Load($Reader)

# Controls
$MainBorder     = $Window.FindName("MainBorder")
$TxtIcon        = $Window.FindName("TxtIcon")
$TxtWattage     = $Window.FindName("TxtWattage")
$Sep1           = $Window.FindName("Sep1")
$TxtBatteryIcon = $Window.FindName("TxtBatteryIcon")
$TxtPercent     = $Window.FindName("TxtPercent")
$Sep2           = $Window.FindName("Sep2")
$TxtCpuIcon     = $Window.FindName("TxtCpuIcon")
$TxtCpuTemp     = $Window.FindName("TxtCpuTemp")
$Sep3           = $Window.FindName("Sep3")
$TxtTimeIcon    = $Window.FindName("TxtTimeIcon")
$TxtRemaining   = $Window.FindName("TxtRemaining")
$BtnClose       = $Window.FindName("BtnClose")

# Apply Settings
$Window.Left = $Settings.Left
$Window.Top = $Settings.Top
$Window.Opacity = $Settings.Opacity
$Window.Topmost = $Settings.Topmost

# Color brush helpers
$BrushCyan      = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#06B6D4")
$BrushCyanLight = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#67E8F9")
$BrushAmber     = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
$BrushAmberLight= [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FDE68A")
$BrushRed       = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
$BrushRedLight  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FCA5A5")
$BrushGreen     = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981")
$BrushGreenLight= [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")

# Helper to save settings
function Save-Settings {
    try {
        $data = @{
            Left = [math]::Round($Window.Left)
            Top = [math]::Round($Window.Top)
            Compact = [bool]$Settings.Compact
            Opacity = [double]$Window.Opacity
            Interval = [int]$Timer.Interval.TotalSeconds
            Topmost = [bool]$Window.Topmost
        }
        $data | ConvertTo-Json | Set-Content -Path $SettingsFile -Force
    } catch {}
}

# Toggle Compact Mode
function Set-CompactMode([bool]$isCompact) {
    $Settings.Compact = $isCompact
    $vis = if ($isCompact) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    
    # In compact mode, keep Wattage and CPU Temp, hide battery percent & time remaining
    $Sep1.Visibility = [System.Windows.Visibility]::Collapsed
    $TxtBatteryIcon.Visibility = [System.Windows.Visibility]::Collapsed
    $TxtPercent.Visibility = [System.Windows.Visibility]::Collapsed
    $Sep3.Visibility = $vis
    $TxtTimeIcon.Visibility = $vis
    $TxtRemaining.Visibility = $vis
    
    if (-not $isCompact) {
        $Sep1.Visibility = [System.Windows.Visibility]::Visible
        $TxtBatteryIcon.Visibility = [System.Windows.Visibility]::Visible
        $TxtPercent.Visibility = [System.Windows.Visibility]::Visible
    }

    if ($isCompact) {
        $MainBorder.Padding = New-Object System.Windows.Thickness(10, 5, 8, 5)
        $MenuCompact.IsChecked = $true
        if ($TrayMenuCompact) { $TrayMenuCompact.Checked = $true }
    } else {
        $MainBorder.Padding = New-Object System.Windows.Thickness(12, 6, 10, 6)
        $MenuCompact.IsChecked = $false
        if ($TrayMenuCompact) { $TrayMenuCompact.Checked = $false }
    }
}

# ----------------- Overlay Context Menu -----------------
$ContextMenu = New-Object System.Windows.Controls.ContextMenu
$ContextMenu.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E24")
$ContextMenu.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F1F5F9")
$ContextMenu.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#33FFFFFF")

# Menu Item: Compact Mode
$MenuCompact = New-Object System.Windows.Controls.MenuItem
$MenuCompact.Header = "Compact Mode (Double-Click)"
$MenuCompact.IsCheckable = $true
$MenuCompact.IsChecked = $Settings.Compact
$MenuCompact.Add_Click({
    Set-CompactMode (-not $Settings.Compact)
    Save-Settings
})
$ContextMenu.Items.Add($MenuCompact) | Out-Null

# Menu Item: Always On Top
$MenuTopmost = New-Object System.Windows.Controls.MenuItem
$MenuTopmost.Header = "Always on Top"
$MenuTopmost.IsCheckable = $true
$MenuTopmost.IsChecked = $Window.Topmost
$MenuTopmost.Add_Click({
    $Window.Topmost = -not $Window.Topmost
    $MenuTopmost.IsChecked = $Window.Topmost
    Save-Settings
})
$ContextMenu.Items.Add($MenuTopmost) | Out-Null

# Menu Item: Opacity submenu
$MenuOpacity = New-Object System.Windows.Controls.MenuItem
$MenuOpacity.Header = "Opacity"
foreach ($op in @(1.0, 0.90, 0.75, 0.55)) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = "$([int]($op * 100))%"
    $val = $op
    $item.Add_Click({
        $Window.Opacity = $val
        Save-Settings
    }.GetNewClosure())
    $MenuOpacity.Items.Add($item) | Out-Null
}
$ContextMenu.Items.Add($MenuOpacity) | Out-Null

# Menu Item: Refresh Interval submenu
$MenuInterval = New-Object System.Windows.Controls.MenuItem
$MenuInterval.Header = "Refresh Rate"
foreach ($sec in @(1, 2, 5)) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = "$sec second$(if ($sec -gt 1) {'s'})"
    $s = $sec
    $item.Add_Click({
        $Timer.Interval = [TimeSpan]::FromSeconds($s)
        Save-Settings
    }.GetNewClosure())
    $MenuInterval.Items.Add($item) | Out-Null
}
$ContextMenu.Items.Add($MenuInterval) | Out-Null

$ContextMenu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

# Menu Item: Reset Position
$MenuReset = New-Object System.Windows.Controls.MenuItem
$MenuReset.Header = "Reset to Top Right"
$MenuReset.Add_Click({
    $Window.Left = [System.Windows.SystemParameters]::PrimaryScreenWidth - 360
    $Window.Top = 30
    Save-Settings
})
$ContextMenu.Items.Add($MenuReset) | Out-Null

# Menu Item: Hide to Tray
$MenuHide = New-Object System.Windows.Controls.MenuItem
$MenuHide.Header = "Hide to Hidden Icons"
$MenuHide.Add_Click({
    $Window.Hide()
})
$ContextMenu.Items.Add($MenuHide) | Out-Null

# Menu Item: Exit
$MenuExit = New-Object System.Windows.Controls.MenuItem
$MenuExit.Header = "Exit Completely"
$MenuExit.Add_Click({
    Exit-Application
})
$ContextMenu.Items.Add($MenuExit) | Out-Null

$MainBorder.ContextMenu = $ContextMenu

# ----------------- System Tray (Hidden Icons) Integration -----------------
# Generate clean tray icon using GDI+
$trayBmp = New-Object System.Drawing.Bitmap(16, 16)
$trayG = [System.Drawing.Graphics]::FromImage($trayBmp)
$trayG.Clear([System.Drawing.Color]::Transparent)
$trayBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(6, 182, 212)) # Cyan
$trayFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$trayG.DrawString($IconBolt, $trayFont, $trayBrush, -2, -2)
$trayG.Dispose()
$trayHicon = $trayBmp.GetHicon()
$trayIcon = [System.Drawing.Icon]::FromHandle($trayHicon)

$NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$NotifyIcon.Icon = $trayIcon
$NotifyIcon.Text = "Battery & CPU Overlay"
$NotifyIcon.Visible = $true

# System Tray Context Menu
$TrayContextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$TrayMenuToggle = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayMenuToggle.Text = "Toggle Overlay"
$TrayMenuToggle.Font = New-Object System.Drawing.Font($TrayMenuToggle.Font, [System.Drawing.FontStyle]::Bold)
$TrayMenuToggle.Add_Click({
    if ($Window.Visibility -eq [System.Windows.Visibility]::Visible) {
        $Window.Hide()
    } else {
        $Window.Show()
        $Window.Activate()
    }
})
$TrayContextMenu.Items.Add($TrayMenuToggle) | Out-Null

$TrayMenuCompact = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayMenuCompact.Text = "Compact Mode"
$TrayMenuCompact.Checked = $Settings.Compact
$TrayMenuCompact.Add_Click({
    Set-CompactMode (-not $Settings.Compact)
    Save-Settings
})
$TrayContextMenu.Items.Add($TrayMenuCompact) | Out-Null

$TrayMenuReset = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayMenuReset.Text = "Reset to Top Right"
$TrayMenuReset.Add_Click({
    $Window.Left = [System.Windows.SystemParameters]::PrimaryScreenWidth - 360
    $Window.Top = 30
    $Window.Show()
    Save-Settings
})
$TrayContextMenu.Items.Add($TrayMenuReset) | Out-Null

$TrayContextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$TrayMenuExit = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayMenuExit.Text = "Exit"
$TrayMenuExit.Add_Click({
    Exit-Application
})
$TrayContextMenu.Items.Add($TrayMenuExit) | Out-Null

$NotifyIcon.ContextMenuStrip = $TrayContextMenu

# Clicking the Tray icon toggles overlay visibility
$NotifyIcon.Add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($Window.Visibility -eq [System.Windows.Visibility]::Visible) {
            $Window.Hide()
        } else {
            $Window.Show()
            $Window.Activate()
        }
    }
})

function Exit-Application {
    $script:IsShuttingDown = $true
    Save-Settings
    $Timer.Stop()
    $NotifyIcon.Visible = $false
    $NotifyIcon.Dispose()
    [System.Windows.Application]::Current.Shutdown()
}

# Drag window & Double-click toggle
$MainBorder.Add_MouseLeftButtonDown({
    param($sender, $e)
    if ($e.ClickCount -eq 2) {
        Set-CompactMode (-not $Settings.Compact)
        Save-Settings
    } elseif ($e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        try {
            $Window.DragMove()
            Save-Settings
        } catch {}
    }
})

# Close button hides to Hidden Icons instead of terminating
$script:HasShownHideNotice = $false
$BtnClose.Add_MouseEnter({
    $BtnClose.Foreground = $BrushRed
})
$BtnClose.Add_MouseLeave({
    $BtnClose.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
})
$BtnClose.Add_Click({
    Save-Settings
    $Window.Hide()
    if (-not $script:HasShownHideNotice) {
        $script:HasShownHideNotice = $true
        $NotifyIcon.ShowBalloonTip(2500, "Battery & CPU Overlay", "Minimized to Hidden Icons tray. Click the lightning icon anytime to reopen.", [System.Windows.Forms.ToolTipIcon]::Info)
    }
})

# Cache full charged capacity
$script:FullCapacity = 31759
try {
    $capObj = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue
    if ($capObj -and $capObj.FullChargedCapacity -gt 0) {
        $script:FullCapacity = $capObj.FullChargedCapacity
    }
} catch {}

# Realtime update function
function Update-BatteryStats {
    try {
        # 1. Battery Query
        $batterySearcher = New-Object System.Management.ManagementObjectSearcher("root\wmi", "SELECT DischargeRate, ChargeRate, RemainingCapacity, Charging, Discharging, PowerOnline FROM BatteryStatus")
        $b = $batterySearcher.Get() | Select-Object -First 1

        # 2. CPU Temperature Query (unprivileged high-precision thermal zone)
        $tempSearcher = New-Object System.Management.ManagementObjectSearcher("root\cimv2", "SELECT HighPrecisionTemperature, Temperature FROM Win32_PerfFormattedData_Counters_ThermalZoneInformation")
        $tObj = $tempSearcher.Get() | Select-Object -First 1

        $celsius = 0
        if ($tObj) {
            $rawK = if ($tObj["HighPrecisionTemperature"]) { [double]$tObj["HighPrecisionTemperature"] / 10.0 } else { [double]$tObj["Temperature"] }
            if ($rawK -gt 250 -and $rawK -lt 450) {
                $celsius = [math]::Round($rawK - 273.15, 0)
                $TxtCpuTemp.Text = "$celsius" + [char]0x00B0 + "C"

                if ($celsius -ge 78) {
                    $TxtCpuIcon.Foreground = $BrushRed
                    $TxtCpuTemp.Foreground = $BrushRedLight
                } elseif ($celsius -ge 65) {
                    $TxtCpuIcon.Foreground = $BrushAmber
                    $TxtCpuTemp.Foreground = $BrushAmberLight
                } else {
                    $TxtCpuIcon.Foreground = $BrushCyan
                    $TxtCpuTemp.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
                }
            }
        }

        if (-not $b) { return }

        $dischargeRate = [double]$b["DischargeRate"]
        $chargeRate = [double]$b["ChargeRate"]
        $remaining = [double]$b["RemainingCapacity"]
        $charging = [bool]$b["Charging"]
        $discharging = [bool]$b["Discharging"]
        $powerOnline = [bool]$b["PowerOnline"]

        # Battery percentage
        $pct = [System.Windows.Forms.SystemInformation]::PowerStatus.BatteryLifePercent
        if ($pct -gt 0) {
            $percentInt = [int]($pct * 100)
        } else {
            $percentInt = [int](($remaining / $script:FullCapacity) * 100)
        }
        $TxtPercent.Text = "$percentInt%"

        # Battery icon based on percent
        if ($percentInt -le 20) {
            $TxtBatteryIcon.Text = $IconBatLow
            $TxtBatteryIcon.Foreground = $BrushRed
        } else {
            $TxtBatteryIcon.Text = $IconBat
            $TxtBatteryIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
        }

        # Wattage and Power State
        $statusSummary = ""
        if ($powerOnline -or $charging) {
            # Plugged in to AC
            if ($chargeRate -gt 0) {
                $chargeWatts = [math]::Round($chargeRate / 1000, 1)
                $TxtWattage.Text = "+$chargeWatts W"
                $statusSummary = "Charging (+$chargeWatts W)"
            } else {
                $TxtWattage.Text = "AC Power"
                $statusSummary = "AC Power"
            }

            $TxtIcon.Text = $IconBolt
            $TxtIcon.Foreground = $BrushGreen
            $TxtWattage.Foreground = $BrushGreenLight
            $TxtTimeIcon.Text = $IconPlug
            
            if ($percentInt -ge 99 -or ($percentInt -ge 79 -and $chargeRate -eq 0)) {
                $TxtRemaining.Text = "Full / Capped"
            } elseif ($chargeRate -gt 0) {
                $hoursToFull = ($script:FullCapacity - $remaining) / $chargeRate
                if ($hoursToFull -gt 0 -and $hoursToFull -lt 24) {
                    $hrs = [int][math]::Floor($hoursToFull)
                    $mins = [int][math]::Round(($hoursToFull - $hrs) * 60)
                    $TxtRemaining.Text = "$hrs" + "h " + "$mins" + "m to full"
                } else {
                    $TxtRemaining.Text = "Charging"
                }
            } else {
                $TxtRemaining.Text = "Plugged in"
            }
        } else {
            # Discharging on Battery
            $watts = [math]::Round($dischargeRate / 1000, 1)
            $TxtWattage.Text = "$watts W"
            $TxtTimeIcon.Text = $IconClock
            $statusSummary = "$watts W"

            # Color coding based on energy draw efficiency
            if ($watts -le 8.5) {
                # Low power draw / optimal battery life (cyan)
                $TxtIcon.Text = $IconBolt
                $TxtIcon.Foreground = $BrushCyan
                $TxtWattage.Foreground = $BrushCyanLight
            } elseif ($watts -le 15.0) {
                # Normal moderate usage (amber)
                $TxtIcon.Text = $IconBolt
                $TxtIcon.Foreground = $BrushAmber
                $TxtWattage.Foreground = $BrushAmberLight
            } else {
                # High drain (red)
                $TxtIcon.Text = $IconBolt
                $TxtIcon.Foreground = $BrushRed
                $TxtWattage.Foreground = $BrushRedLight
            }

            # Remaining Time calculation
            if ($dischargeRate -gt 0) {
                $hoursLeft = $remaining / $dischargeRate
                $hrs = [int][math]::Floor($hoursLeft)
                $mins = [int][math]::Round(($hoursLeft - $hrs) * 60)
                $TxtRemaining.Text = "$hrs" + "h " + "$mins" + "m left"
            } else {
                $TxtRemaining.Text = "Calculating..."
            }
        }

        # Update Tray Tooltip (max 63 chars)
        $trayTip = "Bat: $percentInt% ($statusSummary) | CPU: $celsius`°C"
        if ($trayTip.Length -gt 63) { $trayTip = $trayTip.Substring(0, 63) }
        $NotifyIcon.Text = $trayTip

    } catch {
        # Fallback if WMI query hiccups
    }
}

# Initial state
Set-CompactMode $Settings.Compact
Update-BatteryStats

# Timer for real-time polling (2s default interval)
$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromSeconds($Settings.Interval)
$Timer.Add_Tick({ Update-BatteryStats })
$Timer.Start()

# Window Closing Event: hide instead of exiting so it stays in Hidden Icons tray
$Window.Add_Closing({
    param($s, $e)
    # If app is shutting down naturally from Exit-Application, allow close
    if (-not $script:IsShuttingDown) {
        $e.Cancel = $true
        $Window.Hide()
        Save-Settings
    }
})

# Show Overlay
$App = New-Object System.Windows.Application
$App.Run($Window) | Out-Null
