# Real-Time Battery Wattage, CPU Temperature & Active Battery Session Tracker
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

# Default settings
$Settings = @{
    Left = [System.Windows.SystemParameters]::PrimaryScreenWidth - 380
    Top = 30
    Compact = $false
    Opacity = 0.90
    Interval = 1
    Topmost = $true
    ShowSessionCard = $true
}

# Session State - Tracks ACTIVE awake time only (pauses in sleep)
$SessionState = @{
    IsActive = $false
    ActiveSeconds = 0.0          # Accumulated ACTIVE awake seconds only
    StartTime = $null            # ISO string when battery session began
    StartPercent = 0             # Battery % when AC was disconnected
    StartMWh = 0.0               # Battery mWh when AC was disconnected
    LastDuration = "00:00:00"    # Final active duration of last session
    LastUsedPercent = 0          # Final % dropped in last session
    LastUsedWh = 0.0             # Final Wh consumed in last session
    LastAvgWatts = 0.0           # Final average wattage in last session
    HasLastSession = $false
    LastDisconnectTime = $null   # Timestamp of latest AC disconnect event
}

# Load settings if available
if (Test-Path $SettingsFile) {
    try {
        $Loaded = Get-Content $SettingsFile -Raw | ConvertFrom-Json
        if ($Loaded.Left) { $Settings.Left = [double]$Loaded.Left }
        if ($Loaded.Top) { $Settings.Top = [double]$Loaded.Top }
        if ($null -ne $Loaded.Compact) { $Settings.Compact = [bool]$Loaded.Compact }
        if ($Loaded.Opacity) { $Settings.Opacity = [double]$Loaded.Opacity }
        if ($Loaded.Interval) { $Settings.Interval = [int]$Loaded.Interval }
        if ($null -ne $Loaded.Topmost) { $Settings.Topmost = [bool]$Loaded.Topmost }
        if ($null -ne $Loaded.ShowSessionCard) { $Settings.ShowSessionCard = [bool]$Loaded.ShowSessionCard }
        
        # Load saved session
        if ($Loaded.SessionState) {
            $ss = $Loaded.SessionState
            if ($ss.StartTime) { $SessionState.StartTime = [string]$ss.StartTime }
            if ($null -ne $ss.ActiveSeconds) { $SessionState.ActiveSeconds = [double]$ss.ActiveSeconds }
            if ($ss.StartPercent) { $SessionState.StartPercent = [int]$ss.StartPercent }
            if ($ss.StartMWh) { $SessionState.StartMWh = [double]$ss.StartMWh }
            if ($null -ne $ss.IsActive) { $SessionState.IsActive = [bool]$ss.IsActive }
            if ($ss.LastDuration) { $SessionState.LastDuration = [string]$ss.LastDuration }
            if ($ss.LastUsedPercent) { $SessionState.LastUsedPercent = [int]$ss.LastUsedPercent }
            if ($ss.LastUsedWh) { $SessionState.LastUsedWh = [double]$ss.LastUsedWh }
            if ($ss.LastAvgWatts) { $SessionState.LastAvgWatts = [double]$ss.LastAvgWatts }
            if ($null -ne $ss.HasLastSession) { $SessionState.HasLastSession = [bool]$ss.HasLastSession }
            if ($ss.LastDisconnectTime) { $SessionState.LastDisconnectTime = [string]$ss.LastDisconnectTime }
        }
    } catch {}
}

# Ensure position is visible within virtual screen bounds
$VirtualWidth = [System.Windows.SystemParameters]::VirtualScreenWidth
$VirtualHeight = [System.Windows.SystemParameters]::VirtualScreenHeight
if ($Settings.Left -lt 0 -or $Settings.Left -gt ($VirtualWidth - 80)) {
    $Settings.Left = [System.Windows.SystemParameters]::PrimaryScreenWidth - 380
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
    <Border Name="MainBorder" Background="#EE16161A" BorderBrush="#33FFFFFF" BorderThickness="1" CornerRadius="16" Padding="12,7,12,7" Margin="8">
        <Border.Effect>
            <DropShadowEffect BlurRadius="14" Opacity="0.45" ShadowDepth="2" Direction="270" Color="#000000"/>
        </Border.Effect>
        <StackPanel Orientation="Vertical">
            <!-- Top Row: Primary Live Status Bar -->
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

                <!-- Toggle Session Card Button -->
                <Button Name="BtnToggleCard" Content="&#x25BE;" Width="18" Height="18" Margin="8,0,0,0"
                        Background="Transparent" BorderThickness="0" Foreground="#94A3B8" FontSize="11"
                        VerticalAlignment="Center" Cursor="Hand" ToolTip="Toggle Battery Session Tracker Card">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="9">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Button.Template>
                </Button>

                <!-- Hide / Close Button -->
                <Button Name="BtnClose" Content="&#x2715;" Width="18" Height="18" Margin="3,0,0,0"
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

            <!-- Bottom Row: Dynamic Battery Session Tracking Card -->
            <Border Name="CardSession" Background="#CC111116" BorderBrush="#24FFFFFF" BorderThickness="1" CornerRadius="10" Margin="0,6,0,1" Padding="10,6,10,6" Visibility="Visible">
                <StackPanel Orientation="Vertical">
                    <!-- Header Row: Title & Running Timer -->
                    <Grid Margin="0,0,0,3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <!-- Session Title & Icon -->
                        <StackPanel Orientation="Horizontal" Grid.Column="0" VerticalAlignment="Center">
                            <TextBlock Name="TxtSessionTitleIcon" Text="&#x1F50B;" FontSize="11" Margin="0,0,4,0"/>
                            <TextBlock Name="TxtSessionTitle" Text="Battery Session (Active)" FontSize="11" FontWeight="SemiBold" Foreground="#38BDF8"/>
                        </StackPanel>

                        <!-- Running Timer (HH:MM:SS) - Active Awake Time -->
                        <StackPanel Orientation="Horizontal" Grid.Column="1" VerticalAlignment="Center">
                            <TextBlock Text="&#x23F1;" FontSize="10" Foreground="#94A3B8" Margin="0,0,3,0"/>
                            <TextBlock Name="TxtSessionTimer" Text="00:00:00" FontSize="11.5" FontWeight="SemiBold" Foreground="#F8FAFC" FontFamily="Consolas, Segoe UI"/>
                        </StackPanel>
                    </Grid>

                    <!-- Metrics Row: Start %, Used %, Energy Wh & Avg Watts -->
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Name="TxtSessionStart" Text="Start: --%" FontSize="10.5" Foreground="#94A3B8"/>

                        <TextBlock Text="&#x2022;" FontSize="9" Foreground="#475569" Margin="6,0,6,0" VerticalAlignment="Center"/>

                        <TextBlock Name="TxtSessionUsed" Text="Used: 0%" FontSize="10.5" FontWeight="SemiBold" Foreground="#FBBF24"/>

                        <TextBlock Text="&#x2022;" FontSize="9" Foreground="#475569" Margin="6,0,6,0" VerticalAlignment="Center"/>

                        <TextBlock Name="TxtSessionEnergy" Text="-0.0 Wh" FontSize="10.5" Foreground="#CBD5E1"/>
                    </StackPanel>
                </StackPanel>
            </Border>
        </StackPanel>
    </Border>
</Window>
"@

$Reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($Xaml))
$Window = [System.Windows.Markup.XamlReader]::Load($Reader)

# Controls
$MainBorder          = $Window.FindName("MainBorder")
$TxtIcon             = $Window.FindName("TxtIcon")
$TxtWattage          = $Window.FindName("TxtWattage")
$Sep1                = $Window.FindName("Sep1")
$TxtBatteryIcon      = $Window.FindName("TxtBatteryIcon")
$TxtPercent          = $Window.FindName("TxtPercent")
$Sep2                = $Window.FindName("Sep2")
$TxtCpuIcon          = $Window.FindName("TxtCpuIcon")
$TxtCpuTemp          = $Window.FindName("TxtCpuTemp")
$Sep3                = $Window.FindName("Sep3")
$TxtTimeIcon         = $Window.FindName("TxtTimeIcon")
$TxtRemaining        = $Window.FindName("TxtRemaining")
$BtnToggleCard       = $Window.FindName("BtnToggleCard")
$BtnClose            = $Window.FindName("BtnClose")

$CardSession         = $Window.FindName("CardSession")
$TxtSessionTitleIcon = $Window.FindName("TxtSessionTitleIcon")
$TxtSessionTitle     = $Window.FindName("TxtSessionTitle")
$TxtSessionTimer     = $Window.FindName("TxtSessionTimer")
$TxtSessionStart     = $Window.FindName("TxtSessionStart")
$TxtSessionUsed      = $Window.FindName("TxtSessionUsed")
$TxtSessionEnergy    = $Window.FindName("TxtSessionEnergy")

# Apply Settings
$Window.Left = $Settings.Left
$Window.Top = $Settings.Top
$Window.Opacity = $Settings.Opacity
$Window.Topmost = $Settings.Topmost

# Color brush helpers
$BrushCyan       = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#06B6D4")
$BrushCyanLight  = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#67E8F9")
$BrushAmber      = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
$BrushAmberLight = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FDE68A")
$BrushRed        = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
$BrushRedLight   = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FCA5A5")
$BrushGreen      = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981")
$BrushGreenLight = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
$BrushSky        = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")

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
            ShowSessionCard = [bool]$Settings.ShowSessionCard
            SessionState = $SessionState
        }
        $data | ConvertTo-Json -Depth 4 | Set-Content -Path $SettingsFile -Force
    } catch {}
}

# Toggle Session Card Visibility
function Set-SessionCardVisibility([bool]$visible) {
    $Settings.ShowSessionCard = $visible
    if ($visible -and (-not $Settings.Compact)) {
        $CardSession.Visibility = [System.Windows.Visibility]::Visible
        $BtnToggleCard.Content = [char]::ConvertFromUtf32(0x25BE) # ▾
        $BtnToggleCard.ToolTip = "Collapse Battery Session Card"
        if ($MenuShowCard) { $MenuShowCard.IsChecked = $true }
        if ($TrayMenuCard) { $TrayMenuCard.Checked = $true }
    } else {
        $CardSession.Visibility = [System.Windows.Visibility]::Collapsed
        $BtnToggleCard.Content = [char]::ConvertFromUtf32(0x25B4) # ▴
        $BtnToggleCard.ToolTip = "Expand Battery Session Card"
        if ($MenuShowCard) { $MenuShowCard.IsChecked = $false }
        if ($TrayMenuCard) { $TrayMenuCard.Checked = $false }
    }
}

# Toggle Compact Mode
function Set-CompactMode([bool]$isCompact) {
    $Settings.Compact = $isCompact
    $vis = if ($isCompact) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    
    $Sep1.Visibility = [System.Windows.Visibility]::Collapsed
    $TxtBatteryIcon.Visibility = [System.Windows.Visibility]::Collapsed
    $TxtPercent.Visibility = [System.Windows.Visibility]::Collapsed
    $Sep3.Visibility = $vis
    $TxtTimeIcon.Visibility = $vis
    $TxtRemaining.Visibility = $vis
    $BtnToggleCard.Visibility = $vis
    
    if (-not $isCompact) {
        $Sep1.Visibility = [System.Windows.Visibility]::Visible
        $TxtBatteryIcon.Visibility = [System.Windows.Visibility]::Visible
        $TxtPercent.Visibility = [System.Windows.Visibility]::Visible
        Set-SessionCardVisibility $Settings.ShowSessionCard
    } else {
        $CardSession.Visibility = [System.Windows.Visibility]::Collapsed
    }

    if ($isCompact) {
        $MainBorder.Padding = New-Object System.Windows.Thickness(10, 5, 8, 5)
        $MenuCompact.IsChecked = $true
        if ($TrayMenuCompact) { $TrayMenuCompact.Checked = $true }
    } else {
        $MainBorder.Padding = New-Object System.Windows.Thickness(12, 7, 12, 7)
        $MenuCompact.IsChecked = $false
        if ($TrayMenuCompact) { $TrayMenuCompact.Checked = $false }
    }
}

$BtnToggleCard.Add_Click({
    Set-SessionCardVisibility (-not $Settings.ShowSessionCard)
    Save-Settings
})

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

# Menu Item: Show Session Tracker Card
$MenuShowCard = New-Object System.Windows.Controls.MenuItem
$MenuShowCard.Header = "Show Session Tracker Card"
$MenuShowCard.IsCheckable = $true
$MenuShowCard.IsChecked = $Settings.ShowSessionCard
$MenuShowCard.Add_Click({
    Set-SessionCardVisibility (-not $Settings.ShowSessionCard)
    Save-Settings
})
$ContextMenu.Items.Add($MenuShowCard) | Out-Null

# Menu Item: Reset Current Battery Session
$MenuResetSession = New-Object System.Windows.Controls.MenuItem
$MenuResetSession.Header = "Reset Session Counter Now"
$MenuResetSession.Add_Click({
    Trigger-ManualReset
})
$ContextMenu.Items.Add($MenuResetSession) | Out-Null

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

$ContextMenu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

# Menu Item: Reset Position
$MenuReset = New-Object System.Windows.Controls.MenuItem
$MenuReset.Header = "Reset to Top Right"
$MenuReset.Add_Click({
    $Window.Left = [System.Windows.SystemParameters]::PrimaryScreenWidth - 380
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
$trayBmp = New-Object System.Drawing.Bitmap(16, 16)
$trayG = [System.Drawing.Graphics]::FromImage($trayBmp)
$trayG.Clear([System.Drawing.Color]::Transparent)
$trayBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(6, 182, 212))
$trayFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$trayG.DrawString($IconBolt, $trayFont, $trayBrush, -2, -2)
$trayG.Dispose()
$trayHicon = $trayBmp.GetHicon()
$trayIcon = [System.Drawing.Icon]::FromHandle($trayHicon)

$NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$NotifyIcon.Icon = $trayIcon
$NotifyIcon.Text = "Battery & Session Tracker"
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

$TrayMenuCard = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayMenuCard.Text = "Show Session Tracker Card"
$TrayMenuCard.Checked = $Settings.ShowSessionCard
$TrayMenuCard.Add_Click({
    Set-SessionCardVisibility (-not $Settings.ShowSessionCard)
    Save-Settings
})
$TrayContextMenu.Items.Add($TrayMenuCard) | Out-Null

$TrayMenuResetCounter = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayMenuResetCounter.Text = "Reset Session Counter"
$TrayMenuResetCounter.Add_Click({
    Trigger-ManualReset
})
$TrayContextMenu.Items.Add($TrayMenuResetCounter) | Out-Null

$TrayMenuReset = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayMenuReset.Text = "Reset to Top Right"
$TrayMenuReset.Add_Click({
    $Window.Left = [System.Windows.SystemParameters]::PrimaryScreenWidth - 380
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
    try {
        [Microsoft.Win32.SystemEvents]::remove_PowerModeChanged($script:PowerModeHandler)
    } catch {}
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
        $NotifyIcon.ShowBalloonTip(2500, "Battery & Session Tracker", "Minimized to Hidden Icons tray. Click the lightning icon anytime to reopen.", [System.Windows.Forms.ToolTipIcon]::Info)
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

# Helper: Query latest AC disconnect event from Windows Kernel-Power
function Get-LatestDisconnectEvent {
    try {
        $events = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'} -MaxEvents 25 -ErrorAction SilentlyContinue
        foreach ($e in $events) {
            if ($e.Id -eq 105 -and $e.Properties.Count -ge 2) {
                $acOnline = [bool]$e.Properties[0].Value
                if (-not $acOnline) {
                    # Most recent disconnect event
                    return $e
                }
            }
        }
    } catch {}
    return $null
}

# Helper: Start clean new battery session (Reset)
function Start-NewBatterySession([double]$mwh, [int]$pct, [DateTime]$eventTime) {
    $script:SessionState.IsActive = $true
    $script:SessionState.ActiveSeconds = 0.0
    
    if ($eventTime) {
        $script:SessionState.StartTime = $eventTime.ToString("o")
        $script:SessionState.LastDisconnectTime = $eventTime.ToString("o")
    } else {
        $script:SessionState.StartTime = [DateTime]::Now.ToString("o")
        $script:SessionState.LastDisconnectTime = [DateTime]::Now.ToString("o")
    }
    
    $script:SessionState.StartMWh = $mwh
    $script:SessionState.StartPercent = $pct
    $script:SessionState.LastDuration = "00:00:00"
    $script:LastTickTime = [DateTime]::UtcNow
    Save-Settings
}

# Helper: End battery session when AC is plugged in
function End-BatterySession([double]$mwh, [int]$pct) {
    if ($script:SessionState.IsActive) {
        $totalSec = [int][math]::Floor($script:SessionState.ActiveSeconds)
        $hrs = [math]::Floor($totalSec / 3600)
        $mins = [math]::Floor(($totalSec % 3600) / 60)
        $secs = $totalSec % 60
        $script:SessionState.LastDuration = [string]::Format("{0:D2}:{1:D2}:{2:D2}", $hrs, $mins, $secs)
        
        $drop = $script:SessionState.StartPercent - $pct
        $script:SessionState.LastUsedPercent = if ($drop -gt 0) { $drop } else { 0 }
        
        $mwhUsed = $script:SessionState.StartMWh - $mwh
        $whUsed = if ($mwhUsed -gt 0) { [math]::Round($mwhUsed / 1000, 1) } else { 0.0 }
        $script:SessionState.LastUsedWh = $whUsed
        
        $hoursActive = $script:SessionState.ActiveSeconds / 3600.0
        $script:SessionState.LastAvgWatts = if ($hoursActive -gt 0.008) { [math]::Round($whUsed / $hoursActive, 1) } else { 0.0 }
        
        $script:SessionState.HasLastSession = $true
        $script:SessionState.IsActive = $false
        Save-Settings
    }
}

# Manual Reset trigger from menu
function Trigger-ManualReset {
    try {
        $b = (New-Object System.Management.ManagementObjectSearcher("root\wmi", "SELECT RemainingCapacity FROM BatteryStatus")).Get() | Select-Object -First 1
        $rem = if ($b) { [double]$b["RemainingCapacity"] } else { $script:FullCapacity }
        $pct = [int]([System.Windows.Forms.SystemInformation]::PowerStatus.BatteryLifePercent * 100)
        Start-NewBatterySession $rem $pct ([DateTime]::Now)
    } catch {}
}

# State tracking variables
$script:LastKnownPowerOnline = $null
$script:LastTickTime = [DateTime]::UtcNow

# OS Power Broadcast Listener: detects sleep/resume and AC plug/unplug instantly
$script:PowerModeHandler = {
    param($s, $e)
    try {
        if ($e.Mode -eq [Microsoft.Win32.PowerModes]::Suspend) {
            $script:LastTickTime = [DateTime]::UtcNow
        } elseif ($e.Mode -eq [Microsoft.Win32.PowerModes]::Resume) {
            # Waking from sleep: reset tick timer so sleeping hours are NEVER added!
            $script:LastTickTime = [DateTime]::UtcNow
            Update-BatteryStats
        } elseif ($e.Mode -eq [Microsoft.Win32.PowerModes]::StatusChange) {
            # Power status changed (AC plugged / unplugged)
            Update-BatteryStats
        }
    } catch {}
}
[Microsoft.Win32.SystemEvents]::add_PowerModeChanged($script:PowerModeHandler)

# Realtime update function (called every 1 second)
function Update-BatteryStats {
    try {
        $nowUtc = [DateTime]::UtcNow
        
        # ----------------- Awake Time Accumulation (No Sleep Counting!) -----------------
        $delta = 0.0
        if ($null -ne $script:LastTickTime) {
            $delta = ($nowUtc - $script:LastTickTime).TotalSeconds
        }
        $script:LastTickTime = $nowUtc

        # If delta is >= 2.5 seconds on a 1-second timer, the laptop was asleep / in Modern Standby!
        $wasSleeping = ($delta -ge 2.5)

        # 1. Check Power Status
        $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
        $isAcOnline = ($powerStatus.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)

        # 2. Battery WMI Query
        $batterySearcher = New-Object System.Management.ManagementObjectSearcher("root\wmi", "SELECT DischargeRate, ChargeRate, RemainingCapacity, Charging, Discharging, PowerOnline FROM BatteryStatus")
        $b = $batterySearcher.Get() | Select-Object -First 1
        if (-not $b) { return }

        $dischargeRate = [double]$b["DischargeRate"]
        $chargeRate = [double]$b["ChargeRate"]
        $remaining = [double]$b["RemainingCapacity"]
        $charging = [bool]$b["Charging"]
        $discharging = [bool]$b["Discharging"]
        $wmiPowerOnline = [bool]$b["PowerOnline"]

        # Final Power State (True = AC connected, False = Discharging on Battery)
        $currentPowerOnline = $isAcOnline -or $wmiPowerOnline

        # Battery percentage
        $pctFloat = $powerStatus.BatteryLifePercent
        $percentInt = if ($pctFloat -gt 0) { [int]($pctFloat * 100) } else { [int](($remaining / $script:FullCapacity) * 100) }
        $TxtPercent.Text = "$percentInt%"

        if ($percentInt -le 20) {
            $TxtBatteryIcon.Text = $IconBatLow
            $TxtBatteryIcon.Foreground = $BrushRed
        } else {
            $TxtBatteryIcon.Text = $IconBat
            $TxtBatteryIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
        }

        # 3. CPU Temperature Query
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

        # ----------------- Guaranteed AC Disconnect Detection & Lifecycle -----------------
        if ($null -ne $script:LastKnownPowerOnline) {
            if ($script:LastKnownPowerOnline -and (-not $currentPowerOnline)) {
                # Live transition: AC -> Battery (Unplugged right now!)
                Start-NewBatterySession $remaining $percentInt ([DateTime]::Now)
            } elseif ((-not $script:LastKnownPowerOnline) -and $currentPowerOnline) {
                # Live transition: Battery -> AC (Plugged in right now!)
                End-BatterySession $remaining $percentInt
            }
        } else {
            # First tick after startup:
            if (-not $currentPowerOnline) {
                # Laptop is currently on battery! Check if a disconnect event occurred
                $latestEvent = Get-LatestDisconnectEvent
                if ($latestEvent) {
                    $evtTime = $latestEvent.TimeCreated
                    $evtMWh = [double]$latestEvent.Properties[1].Value
                    $evtFull = [double]$latestEvent.Properties[2].Value
                    $evtPct = if ($evtFull -gt 0) { [math]::Round(($evtMWh / $evtFull) * 100) } else { $percentInt }
                    
                    # If no active session, or if this disconnect event is NEWER than our recorded session start time:
                    $needsNewSession = $true
                    if ($script:SessionState.IsActive -and $script:SessionState.StartTime) {
                        try {
                            $savedStart = [DateTime]::Parse($script:SessionState.StartTime)
                            # If disconnect event is within 30 seconds of saved start, it's the same session!
                            if ([math]::Abs(($evtTime - $savedStart).TotalSeconds) -lt 45) {
                                $needsNewSession = $false
                            }
                        } catch {}
                    }
                    
                    if ($needsNewSession) {
                        Start-NewBatterySession (if ($evtMWh -gt 0) { $evtMWh } else { $remaining }) $evtPct $evtTime
                    }
                } elseif (-not $script:SessionState.IsActive) {
                    Start-NewBatterySession $remaining $percentInt ([DateTime]::Now)
                }
            }
        }
        $script:LastKnownPowerOnline = $currentPowerOnline

        # Check disconnect events on wake: in case user unplugged while laptop was ASLEEP!
        if ($wasSleeping -and (-not $currentPowerOnline)) {
            $latestEvent = Get-LatestDisconnectEvent
            if ($latestEvent) {
                $evtTime = $latestEvent.TimeCreated
                if ($script:SessionState.StartTime) {
                    try {
                        $currentStart = [DateTime]::Parse($script:SessionState.StartTime)
                        if ($evtTime -gt $currentStart.AddSeconds(10)) {
                            # Unplugged while sleeping! Start fresh session from that disconnect!
                            $evtMWh = [double]$latestEvent.Properties[1].Value
                            $evtFull = [double]$latestEvent.Properties[2].Value
                            $evtPct = if ($evtFull -gt 0) { [math]::Round(($evtMWh / $evtFull) * 100) } else { $percentInt }
                            Start-NewBatterySession (if ($evtMWh -gt 0) { $evtMWh } else { $remaining }) $evtPct $evtTime
                        }
                    } catch {}
                }
            }
        }

        # ----------------- Accumulate Active Seconds (AWAKE ONLY) -----------------
        if ($script:SessionState.IsActive -and (-not $currentPowerOnline)) {
            if (-not $wasSleeping) {
                # System was awake during this tick
                if ($delta -gt 0 -and $delta -lt 2.5) {
                    $script:SessionState.ActiveSeconds += $delta
                } else {
                    $script:SessionState.ActiveSeconds += 1.0
                }
            } else {
                # System just resumed from sleep: only add 1 second for the awake tick
                $script:SessionState.ActiveSeconds += 1.0
            }
        }

        # ----------------- Top Row Live Status Rendering -----------------
        $statusSummary = ""
        if ($currentPowerOnline) {
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

            if ($watts -le 8.5) {
                $TxtIcon.Text = $IconBolt
                $TxtIcon.Foreground = $BrushCyan
                $TxtWattage.Foreground = $BrushCyanLight
            } elseif ($watts -le 15.0) {
                $TxtIcon.Text = $IconBolt
                $TxtIcon.Foreground = $BrushAmber
                $TxtWattage.Foreground = $BrushAmberLight
            } else {
                $TxtIcon.Text = $IconBolt
                $TxtIcon.Foreground = $BrushRed
                $TxtWattage.Foreground = $BrushRedLight
            }

            if ($dischargeRate -gt 0) {
                $hoursLeft = $remaining / $dischargeRate
                $hrs = [int][math]::Floor($hoursLeft)
                $mins = [int][math]::Round(($hoursLeft - $hrs) * 60)
                $TxtRemaining.Text = "$hrs" + "h " + "$mins" + "m left"
            } else {
                $TxtRemaining.Text = "Calculating..."
            }
        }

        # ----------------- Session Tracker Card Rendering -----------------
        $elapsedDisplay = "00:00:00"
        if (-not $currentPowerOnline) {
            # ACTIVE ON BATTERY
            if ($Settings.ShowSessionCard -and (-not $Settings.Compact)) {
                $CardSession.Visibility = [System.Windows.Visibility]::Visible
            }

            $TxtSessionTitleIcon.Text = $IconBat
            $TxtSessionTitle.Text = "Battery Session (Active)"
            $TxtSessionTitle.Foreground = $BrushSky

            # Format Active Seconds (HH:MM:SS)
            $totalSec = [int][math]::Floor($script:SessionState.ActiveSeconds)
            $hrs = [math]::Floor($totalSec / 3600)
            $mins = [math]::Floor(($totalSec % 3600) / 60)
            $secs = $totalSec % 60
            $elapsedDisplay = [string]::Format("{0:D2}:{1:D2}:{2:D2}", $hrs, $mins, $secs)
            $TxtSessionTimer.Text = $elapsedDisplay

            # Start info
            $startDisplay = if ($script:SessionState.StartTime) {
                try { [DateTime]::Parse($script:SessionState.StartTime).ToString("h:mm tt") } catch { "" }
            } else { "" }
            $TxtSessionStart.Text = "Start: $($script:SessionState.StartPercent)% $(if ($startDisplay) { "($startDisplay)" })"

            # Power Consumed (%)
            $pctDropped = $script:SessionState.StartPercent - $percentInt
            if ($pctDropped -lt 0) { $pctDropped = 0 }
            $TxtSessionUsed.Text = "Used: $pctDropped%"

            # Energy Consumed (Wh) & Avg Watts (based on ACTIVE awake hours only!)
            $mwhUsed = $script:SessionState.StartMWh - $remaining
            $whUsed = if ($mwhUsed -gt 0) { [math]::Round($mwhUsed / 1000, 1) } else { 0.0 }
            $hoursActive = $script:SessionState.ActiveSeconds / 3600.0
            $avgWatts = if ($hoursActive -gt 0.008) { [math]::Round($whUsed / $hoursActive, 1) } else { [math]::Round($dischargeRate / 1000, 1) }
            $TxtSessionEnergy.Text = "-$whUsed Wh (Avg $avgWatts W)"
        } else {
            # ON AC POWER (PLUGGED IN)
            if ($script:SessionState.HasLastSession -and $Settings.ShowSessionCard -and (-not $Settings.Compact)) {
                $CardSession.Visibility = [System.Windows.Visibility]::Visible
                $TxtSessionTitleIcon.Text = $IconPlug
                $TxtSessionTitle.Text = "Last Battery Session (Active)"
                $TxtSessionTitle.Foreground = $BrushGreenLight
                $TxtSessionTimer.Text = $script:SessionState.LastDuration
                $TxtSessionStart.Text = "Start: $($script:SessionState.StartPercent)%"
                $TxtSessionUsed.Text = "Used: $($script:SessionState.LastUsedPercent)%"
                $TxtSessionEnergy.Text = "-$($script:SessionState.LastUsedWh) Wh (Avg $($script:SessionState.LastAvgWatts) W)"
            } elseif (-not $script:SessionState.HasLastSession) {
                $CardSession.Visibility = [System.Windows.Visibility]::Collapsed
            }
        }

        # ----------------- Update Tray Tooltip (max 63 chars) -----------------
        $trayTip = if (-not $currentPowerOnline) {
            "Bat: $percentInt% ($statusSummary) | $elapsedDisplay | CPU: $celsius`°C"
        } else {
            "AC Power ($percentInt%) | CPU: $celsius`°C"
        }
        if ($trayTip.Length -gt 63) { $trayTip = $trayTip.Substring(0, 63) }
        $NotifyIcon.Text = $trayTip

    } catch {
        # Fallback if WMI query hiccups
    }
}

# Initial state
Set-CompactMode $Settings.Compact
Set-SessionCardVisibility $Settings.ShowSessionCard
Update-BatteryStats

# Timer for real-time polling (1 second interval)
$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromSeconds($Settings.Interval)
$Timer.Add_Tick({ Update-BatteryStats })
$Timer.Start()

# Window Closing Event: hide instead of exiting so it stays in Hidden Icons tray
$Window.Add_Closing({
    param($s, $e)
    if (-not $script:IsShuttingDown) {
        $e.Cancel = $true
        $Window.Hide()
        Save-Settings
    }
})

# Show Overlay
$App = New-Object System.Windows.Application
$App.Run($Window) | Out-Null
