# Real-Time Battery Wattage, CPU Temperature & Live Battery Session Tracker
# Ultra-lightweight, battery-efficient WPF overlay with System Tray ("Hidden Icons") support

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Management

# Single-instance enforcement: prevent competing duplicate instances
$script:MutexName = "Local\BatteryOverlay_SingleInstance_Mutex"
$script:ShowEventName = "Local\BatteryOverlay_ShowWindow_Event"
$script:CreatedNewMutex = $false
$script:AppMutex = $null

try {
    $script:AppMutex = New-Object System.Threading.Mutex($true, $script:MutexName, [ref]$script:CreatedNewMutex)
} catch [System.Threading.AbandonedMutexException] {
    $script:CreatedNewMutex = $true
} catch {
    $script:CreatedNewMutex = $true
}

if (-not $script:CreatedNewMutex) {
    # Another instance is already running!
    # Signal it to restore and bring its overlay window to the front on screen!
    try {
        $showEv = [System.Threading.EventWaitHandle]::OpenExisting($script:ShowEventName)
        $showEv.Set() | Out-Null
    } catch {}
    exit
}

# Main instance: create show signal event
try {
    $script:ShowEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $script:ShowEventName)
} catch {
    $script:ShowEvent = $null
}

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
    ShowCapacitySlot = $true
    CapacityMode = "Remaining"     # "Remaining", "Detailed", "Full"
}

# Session State - Tracks ACTIVE awake time only (pauses in sleep)
$SessionState = @{
    IsActive = $false
    ActiveSeconds = 0.0          # Accumulated ACTIVE awake seconds only
    StartTime = $null            # ISO string when battery session began
    StartTimeStr = ""            # e.g. "5:30 PM"
    StartPercent = 0             # Battery % when AC was disconnected
    StartMWh = 0.0               # Battery mWh when AC was disconnected
    LastDuration = "00:00:00"    # Final active duration of last session
    LastUsedPercent = 0          # Final % dropped in last session
    LastUsedWh = 0.0             # Final Wh consumed in last session
    LastAvgWatts = 0.0           # Final average wattage in last session
    HasLastSession = $false
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
        if ($null -ne $Loaded.ShowCapacitySlot) { $Settings.ShowCapacitySlot = [bool]$Loaded.ShowCapacitySlot }
        if ($Loaded.CapacityMode) { $Settings.CapacityMode = [string]$Loaded.CapacityMode }
        
        # Load saved session
        if ($Loaded.SessionState) {
            $ss = $Loaded.SessionState
            if ($ss.StartTime) { $SessionState.StartTime = [string]$ss.StartTime }
            if ($ss.StartTimeStr) { $SessionState.StartTimeStr = [string]$ss.StartTimeStr }
            if ($null -ne $ss.ActiveSeconds) { $SessionState.ActiveSeconds = [double]$ss.ActiveSeconds }
            if ($ss.StartPercent) { $SessionState.StartPercent = [int]$ss.StartPercent }
            if ($ss.StartMWh) { $SessionState.StartMWh = [double]$ss.StartMWh }
            if ($null -ne $ss.IsActive) { $SessionState.IsActive = [bool]$ss.IsActive }
            if ($ss.LastDuration) { $SessionState.LastDuration = [string]$ss.LastDuration }
            if ($ss.LastUsedPercent) { $SessionState.LastUsedPercent = [int]$ss.LastUsedPercent }
            if ($ss.LastUsedWh) { $SessionState.LastUsedWh = [double]$ss.LastUsedWh }
            if ($ss.LastAvgWatts) { $SessionState.LastAvgWatts = [double]$ss.LastAvgWatts }
            if ($null -ne $ss.HasLastSession) { $SessionState.HasLastSession = [bool]$ss.HasLastSession }
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
                <!-- Power Icon & Live Wattage -->
                <TextBlock Name="TxtIcon" Text="&#x26A1;" FontSize="13" Foreground="#00F0FF" VerticalAlignment="Center" Margin="0,0,5,0" Cursor="SizeAll"/>
                <TextBlock Name="TxtWattage" Text="-- W" FontSize="13" FontWeight="SemiBold" Foreground="#FFFFFF" VerticalAlignment="Center" Cursor="SizeAll"/>

                <!-- Separator 1 -->
                <Rectangle Name="Sep1" Width="1" Height="14" Fill="#33FFFFFF" Margin="9,0,9,0" VerticalAlignment="Center"/>

                <!-- Battery Percentage (Clickable to toggle % / Wh) -->
                <TextBlock Name="TxtBatteryIcon" Text="&#x1F50B;" FontSize="11" VerticalAlignment="Center" Margin="0,0,3,0" Cursor="Hand" ToolTip="Battery Percentage (Click to toggle % / Wh)"/>
                <TextBlock Name="TxtPercent" Text="--%" FontSize="12.5" FontWeight="Medium" Foreground="#E2E8F0" VerticalAlignment="Center" Cursor="Hand" ToolTip="Battery Percentage (Click to toggle % / Wh)"/>

                <!-- Separator Cap -->
                <Rectangle Name="SepCap" Width="1" Height="14" Fill="#33FFFFFF" Margin="9,0,9,0" VerticalAlignment="Center"/>

                <!-- Capacity Slot (Wh / Detailed / Full) -->
                <StackPanel Name="SlotCapacity" Orientation="Horizontal" VerticalAlignment="Center" Cursor="Hand" ToolTip="Battery Capacity (Click: switch format | Right-click: toggle slot)">
                    <TextBlock Name="TxtCapacityIcon" Text="&#x1F4CA;" FontSize="11" Foreground="#38BDF8" VerticalAlignment="Center" Margin="0,0,3,0"/>
                    <TextBlock Name="TxtCapacity" Text="-- Wh" FontSize="12.5" FontWeight="Medium" Foreground="#E2E8F0" VerticalAlignment="Center"/>
                </StackPanel>

                <!-- Separator 2 -->
                <Rectangle Name="Sep2" Width="1" Height="14" Fill="#33FFFFFF" Margin="9,0,9,0" VerticalAlignment="Center"/>

                <!-- CPU Temperature -->
                <TextBlock Name="TxtCpuIcon" Text="&#x1F321;" FontSize="11" Foreground="#00F0FF" VerticalAlignment="Center" Margin="0,0,3,0" Cursor="SizeAll"/>
                <TextBlock Name="TxtCpuTemp" Text="--&#x00B0;C" FontSize="12.5" FontWeight="Medium" Foreground="#E2E8F0" VerticalAlignment="Center" Cursor="SizeAll"/>

                <!-- Separator 3 -->
                <Rectangle Name="Sep3" Width="1" Height="14" Fill="#33FFFFFF" Margin="9,0,9,0" VerticalAlignment="Center"/>

                <!-- Live Timer / Remaining Time -->
                <TextBlock Name="TxtTimeIcon" Text="&#x23F1;" FontSize="11" Foreground="#38BDF8" VerticalAlignment="Center" Margin="0,0,3,0" Cursor="SizeAll"/>
                <TextBlock Name="TxtRemaining" Text="00:00:00" FontSize="12" FontWeight="SemiBold" Foreground="#F8FAFC" VerticalAlignment="Center" Cursor="SizeAll" FontFamily="Consolas, Segoe UI"/>

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

                    <!-- Metrics Row: Start %, Used %, Energy Wh & Est Remaining -->
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock Name="TxtSessionStart" Text="Started at: --%" FontSize="10.5" Foreground="#94A3B8"/>

                        <TextBlock Text="&#x2022;" FontSize="9" Foreground="#475569" Margin="6,0,6,0" VerticalAlignment="Center"/>

                        <TextBlock Name="TxtSessionUsed" Text="Used: 0%" FontSize="10.5" FontWeight="SemiBold" Foreground="#FBBF24"/>

                        <TextBlock Text="&#x2022;" FontSize="9" Foreground="#475569" Margin="6,0,6,0" VerticalAlignment="Center"/>

                        <TextBlock Name="TxtSessionEnergy" Text="-0.0 Wh" FontSize="10.5" Foreground="#CBD5E1"/>

                        <TextBlock Name="SepSessionEst" Text="&#x2022;" FontSize="9" Foreground="#475569" Margin="6,0,6,0" VerticalAlignment="Center"/>

                        <TextBlock Name="TxtSessionEst" Text="Est: --" FontSize="10.5" Foreground="#94A3B8"/>
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
$SepCap              = $Window.FindName("SepCap")
$SlotCapacity        = $Window.FindName("SlotCapacity")
$TxtCapacityIcon     = $Window.FindName("TxtCapacityIcon")
$TxtCapacity         = $Window.FindName("TxtCapacity")
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
$SepSessionEst       = $Window.FindName("SepSessionEst")
$TxtSessionEst       = $Window.FindName("TxtSessionEst")

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

# Helper to format seconds as HH:MM:SS cleanly without FormatException
function Format-DurationSec([double]$seconds) {
    $total = [int][math]::Floor($seconds)
    if ($total -lt 0) { $total = 0 }
    $h = [int][math]::Floor($total / 3600)
    $m = [int][math]::Floor(($total % 3600) / 60)
    $s = [int]($total % 60)
    return [string]::Format("{0:00}:{1:00}:{2:00}", $h, $m, $s)
}

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
            ShowCapacitySlot = [bool]$Settings.ShowCapacitySlot
            CapacityMode = [string]$Settings.CapacityMode
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

# Toggle Capacity Slot Visibility
function Set-CapacitySlotVisibility([bool]$visible) {
    $Settings.ShowCapacitySlot = $visible
    $vis = if ($visible -and (-not $Settings.Compact)) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $SepCap.Visibility = $vis
    $SlotCapacity.Visibility = $vis
    if ($MenuShowCapacity) { $MenuShowCapacity.IsChecked = $visible }
    if ($TrayMenuShowCapacity) { $TrayMenuShowCapacity.Checked = $visible }
    Save-Settings
}

# Cycle Capacity Format (Remaining Wh -> Detailed Remaining/Full -> Full Capacity)
function Cycle-CapacityMode {
    switch ($Settings.CapacityMode) {
        "Remaining" { $Settings.CapacityMode = "Detailed" }
        "Detailed"  { $Settings.CapacityMode = "Full" }
        default     { $Settings.CapacityMode = "Remaining" }
    }
    Update-CapacityText
    Update-CapacityMenuChecks
    Save-Settings
}

function Set-CapacityMode([string]$mode) {
    $Settings.CapacityMode = $mode
    Update-CapacityText
    Update-CapacityMenuChecks
    Save-Settings
}

function Update-CapacityMenuChecks {
    if ($MenuCapRem)  { $MenuCapRem.IsChecked  = ($Settings.CapacityMode -eq "Remaining") }
    if ($MenuCapDet)  { $MenuCapDet.IsChecked  = ($Settings.CapacityMode -eq "Detailed") }
    if ($MenuCapFull) { $MenuCapFull.IsChecked = ($Settings.CapacityMode -eq "Full") }
    if ($TrayCapRem)  { $TrayCapRem.Checked  = ($Settings.CapacityMode -eq "Remaining") }
    if ($TrayCapDet)  { $TrayCapDet.Checked  = ($Settings.CapacityMode -eq "Detailed") }
    if ($TrayCapFull) { $TrayCapFull.Checked = ($Settings.CapacityMode -eq "Full") }
}

function Update-CapacityText {
    $remWh = [math]::Round($script:CurrentRemainingMWh / 1000.0, 1)
    $fullWh = [math]::Round($script:FullCapacity / 1000.0, 1)
    if ($remWh -le 0 -and $script:FullCapacity -gt 0) {
        $remWh = [math]::Round(($script:FullCapacity * ($script:CurrentPercent / 100.0)) / 1000.0, 1)
    }

    switch ($Settings.CapacityMode) {
        "Detailed" {
            $TxtCapacity.Text = "$remWh / $fullWh Wh"
        }
        "Full" {
            $TxtCapacity.Text = "Cap $fullWh Wh"
        }
        default {
            $TxtCapacity.Text = "$remWh Wh"
        }
    }
    $SlotCapacity.ToolTip = "Battery Capacity: $remWh Wh remaining of $fullWh Wh full charge`nLeft-click: cycle format`nRight-click: toggle slot"
}

# Toggle Compact Mode
function Set-CompactMode([bool]$isCompact) {
    $Settings.Compact = $isCompact
    $vis = if ($isCompact) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    
    $Sep1.Visibility = [System.Windows.Visibility]::Collapsed
    $TxtBatteryIcon.Visibility = [System.Windows.Visibility]::Collapsed
    $TxtPercent.Visibility = [System.Windows.Visibility]::Collapsed
    $SepCap.Visibility = [System.Windows.Visibility]::Collapsed
    $SlotCapacity.Visibility = [System.Windows.Visibility]::Collapsed
    $Sep3.Visibility = $vis
    $TxtTimeIcon.Visibility = $vis
    $TxtRemaining.Visibility = $vis
    $BtnToggleCard.Visibility = $vis
    
    if (-not $isCompact) {
        $Sep1.Visibility = [System.Windows.Visibility]::Visible
        $TxtBatteryIcon.Visibility = [System.Windows.Visibility]::Visible
        $TxtPercent.Visibility = [System.Windows.Visibility]::Visible
        Set-CapacitySlotVisibility $Settings.ShowCapacitySlot
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

# Menu Item: Show Capacity Slot (Wh)
$MenuShowCapacity = New-Object System.Windows.Controls.MenuItem
$MenuShowCapacity.Header = "Show Capacity Slot (Wh)"
$MenuShowCapacity.IsCheckable = $true
$MenuShowCapacity.IsChecked = $Settings.ShowCapacitySlot
$MenuShowCapacity.Add_Click({
    Set-CapacitySlotVisibility (-not $Settings.ShowCapacitySlot)
})
$ContextMenu.Items.Add($MenuShowCapacity) | Out-Null

# Menu Item: Capacity Format submenu
$MenuCapacityMode = New-Object System.Windows.Controls.MenuItem
$MenuCapacityMode.Header = "Capacity Format"

$MenuCapRem = New-Object System.Windows.Controls.MenuItem
$MenuCapRem.Header = "Remaining Only (e.g. 18.9 Wh)"
$MenuCapRem.IsCheckable = $true
$MenuCapRem.IsChecked = ($Settings.CapacityMode -eq "Remaining")
$MenuCapRem.Add_Click({ Set-CapacityMode "Remaining" })
$MenuCapacityMode.Items.Add($MenuCapRem) | Out-Null

$MenuCapDet = New-Object System.Windows.Controls.MenuItem
$MenuCapDet.Header = "Remaining / Full (e.g. 18.9 / 31.8 Wh)"
$MenuCapDet.IsCheckable = $true
$MenuCapDet.IsChecked = ($Settings.CapacityMode -eq "Detailed")
$MenuCapDet.Add_Click({ Set-CapacityMode "Detailed" })
$MenuCapacityMode.Items.Add($MenuCapDet) | Out-Null

$MenuCapFull = New-Object System.Windows.Controls.MenuItem
$MenuCapFull.Header = "Full Capacity (e.g. Cap 31.8 Wh)"
$MenuCapFull.IsCheckable = $true
$MenuCapFull.IsChecked = ($Settings.CapacityMode -eq "Full")
$MenuCapFull.Add_Click({ Set-CapacityMode "Full" })
$MenuCapacityMode.Items.Add($MenuCapFull) | Out-Null

$ContextMenu.Items.Add($MenuCapacityMode) | Out-Null

# Menu Item: Reset Current Battery Session
$MenuResetSession = New-Object System.Windows.Controls.MenuItem
$MenuResetSession.Header = "Reset Battery Session Counter"
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

$TrayMenuShowCapacity = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayMenuShowCapacity.Text = "Show Capacity Slot (Wh)"
$TrayMenuShowCapacity.Checked = $Settings.ShowCapacitySlot
$TrayMenuShowCapacity.Add_Click({
    Set-CapacitySlotVisibility (-not $Settings.ShowCapacitySlot)
})
$TrayContextMenu.Items.Add($TrayMenuShowCapacity) | Out-Null

$TrayMenuCapacityFormat = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayMenuCapacityFormat.Text = "Capacity Format"

$TrayCapRem = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayCapRem.Text = "Remaining Only (Wh)"
$TrayCapRem.Checked = ($Settings.CapacityMode -eq "Remaining")
$TrayCapRem.Add_Click({ Set-CapacityMode "Remaining" })
$TrayMenuCapacityFormat.DropDownItems.Add($TrayCapRem) | Out-Null

$TrayCapDet = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayCapDet.Text = "Remaining / Full (Wh)"
$TrayCapDet.Checked = ($Settings.CapacityMode -eq "Detailed")
$TrayCapDet.Add_Click({ Set-CapacityMode "Detailed" })
$TrayMenuCapacityFormat.DropDownItems.Add($TrayCapDet) | Out-Null

$TrayCapFull = New-Object System.Windows.Forms.ToolStripMenuItem
$TrayCapFull.Text = "Full Capacity (Wh)"
$TrayCapFull.Checked = ($Settings.CapacityMode -eq "Full")
$TrayCapFull.Add_Click({ Set-CapacityMode "Full" })
$TrayMenuCapacityFormat.DropDownItems.Add($TrayCapFull) | Out-Null

$TrayContextMenu.Items.Add($TrayMenuCapacityFormat) | Out-Null

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
    $SaveTimer.Stop()
    $NotifyIcon.Visible = $false
    $NotifyIcon.Dispose()
    try { $script:ShowEvent.Dispose() } catch {}
    try { $script:AppMutex.ReleaseMutex() } catch {}
    try { $script:AppMutex.Dispose() } catch {}
    [System.Windows.Application]::Current.Shutdown()
}

# Left-click on Capacity Slot cycles format (Remaining Wh -> Detailed -> Full)
$SlotCapacity.Add_MouseDown({
    param($s, $e)
    if ($e.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
        Cycle-CapacityMode
        $e.Handled = $true
    }
})

# Left-click on Battery % slot toggles % vs Wh
$script:PercentShowsWh = $false
$PercentClickHandler = {
    param($s, $e)
    if ($e.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
        $script:PercentShowsWh = -not $script:PercentShowsWh
        if ($script:PercentShowsWh) {
            $remWh = [math]::Round($script:CurrentRemainingMWh / 1000.0, 1)
            $TxtPercent.Text = "$remWh Wh"
        } else {
            $TxtPercent.Text = "$($script:CurrentPercent)%"
        }
        $e.Handled = $true
    }
}
$TxtPercent.Add_MouseDown($PercentClickHandler)
$TxtBatteryIcon.Add_MouseDown($PercentClickHandler)

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

# Reset / Start clean new battery session
function Reset-BatterySession([double]$mwh, [int]$pct) {
    $script:SessionState.IsActive = $true
    $script:SessionState.ActiveSeconds = 0.0
    $now = [DateTime]::Now
    $script:SessionState.StartTime = $now.ToString("o")
    $script:SessionState.StartTimeStr = $now.ToString("h:mm tt")
    $script:SessionState.StartMWh = $mwh
    $script:SessionState.StartPercent = $pct
    $script:SessionState.LastDuration = "00:00:00"
    $script:LastTickUtc = [DateTime]::UtcNow
    
    # Auto-expand session card on battery
    Set-SessionCardVisibility $true
    Save-Settings
}

# End battery session when AC is plugged in
function Freeze-BatterySession([double]$mwh, [int]$pct) {
    if ($script:SessionState.IsActive) {
        $script:SessionState.LastDuration = Format-DurationSec $script:SessionState.ActiveSeconds
        
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
        Reset-BatterySession $rem $pct
    } catch {}
}

# State tracking variables
$script:LastIsAc = $null
$script:LastTickUtc = [DateTime]::UtcNow

# OS Power Broadcast Listener: detects sleep/resume and AC plug/unplug instantly
$script:PowerModeHandler = {
    param($s, $e)
    try {
        if ($e.Mode -eq [Microsoft.Win32.PowerModes]::Suspend) {
            $script:LastTickUtc = [DateTime]::UtcNow
        } elseif ($e.Mode -eq [Microsoft.Win32.PowerModes]::Resume) {
            # Waking from sleep: reset tick timer so sleeping hours are NEVER added!
            $script:LastTickUtc = [DateTime]::UtcNow
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
        # Check for external show signal (e.g. user re-launched app via shortcut / Launch.bat)
        if ($script:ShowEvent -and $script:ShowEvent.WaitOne(0)) {
            $Window.WindowState = [System.Windows.WindowState]::Normal
            $Window.Show()
            $Window.Activate()
            $Window.Topmost = [bool]$Settings.Topmost
        }

        $nowUtc = [DateTime]::UtcNow
        
        # ----------------- Awake Time Accumulation (No Sleep Counting!) -----------------
        $delta = 0.0
        if ($null -ne $script:LastTickUtc) {
            $delta = ($nowUtc - $script:LastTickUtc).TotalSeconds
        }
        $script:LastTickUtc = $nowUtc

        # If delta is >= 2.5 seconds on a 1-second timer, the laptop was asleep / in Modern Standby!
        $wasAsleep = ($delta -ge 2.5)

        # 1. Check Power Status
        $powerStatus = [System.Windows.Forms.SystemInformation]::PowerStatus
        $isAc = ($powerStatus.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)
        $onBattery = (-not $isAc)

        # 2. Battery WMI Query
        $batterySearcher = New-Object System.Management.ManagementObjectSearcher("root\wmi", "SELECT DischargeRate, ChargeRate, RemainingCapacity, Charging, Discharging, PowerOnline FROM BatteryStatus")
        $b = $batterySearcher.Get() | Select-Object -First 1
        if (-not $b) { return }

        $dischargeRate = [double]$b["DischargeRate"]
        $chargeRate = [double]$b["ChargeRate"]
        $remaining = [double]$b["RemainingCapacity"]
        $charging = [bool]$b["Charging"]
        $discharging = [bool]$b["Discharging"]

        # Battery percentage & capacity telemetry
        $pctFloat = $powerStatus.BatteryLifePercent
        $percentInt = if ($pctFloat -gt 0) { [int]($pctFloat * 100) } else { [int](($remaining / $script:FullCapacity) * 100) }
        $script:CurrentPercent = $percentInt
        $script:CurrentRemainingMWh = $remaining

        if ($script:PercentShowsWh) {
            $remWh = [math]::Round($remaining / 1000.0, 1)
            $TxtPercent.Text = "$remWh Wh"
        } else {
            $TxtPercent.Text = "$percentInt%"
        }

        # Update Capacity Slot Text & Tooltip
        Update-CapacityText

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

        # ----------------- Guaranteed AC Transition Detection -----------------
        if ($null -ne $script:LastIsAc) {
            if ($script:LastIsAc -and $onBattery) {
                # AC UNPLUGGED! (Transition: AC -> Battery)
                Reset-BatterySession $remaining $percentInt
            } elseif ((-not $script:LastIsAc) -and $isAc) {
                # AC PLUGGED IN! (Transition: Battery -> AC)
                Freeze-BatterySession $remaining $percentInt
            }
        } else {
            # First tick after startup:
            if ($onBattery) {
                if (-not $script:SessionState.IsActive) {
                    Reset-BatterySession $remaining $percentInt
                }
            }
        }
        $script:LastIsAc = $isAc

        # ----------------- Accumulate Active Seconds (AWAKE ONLY) -----------------
        if ($onBattery) {
            if (-not $script:SessionState.IsActive) {
                $script:SessionState.IsActive = $true
                $script:SessionState.StartMWh = $remaining
                $script:SessionState.StartPercent = $percentInt
                $script:SessionState.StartTime = [DateTime]::Now.ToString("o")
                $script:SessionState.StartTimeStr = [DateTime]::Now.ToString("h:mm tt")
            }

            if (-not $wasAsleep) {
                # Normal awake second
                if ($delta -gt 0 -and $delta -lt 2.5) {
                    $script:SessionState.ActiveSeconds += $delta
                } else {
                    $script:SessionState.ActiveSeconds += 1.0
                }
            } else {
                # Just resumed from sleep / Modern Standby:
                # Do NOT add sleep delta! Just add 1 second for awake tick:
                $script:SessionState.ActiveSeconds += 1.0

                # If battery increased by > 3% while asleep, user plugged in and charged while asleep!
                if ($percentInt -gt ($script:SessionState.StartPercent + 3)) {
                    Reset-BatterySession $remaining $percentInt
                }
            }
        }

        # ----------------- Estimate Remaining Hours -----------------
        $estLeftStr = "--"
        if ($dischargeRate -gt 0) {
            $hoursLeft = $remaining / $dischargeRate
            $eH = [int][math]::Floor($hoursLeft)
            $eM = [int][math]::Round(($hoursLeft - $eH) * 60)
            $estLeftStr = "$eH" + "h " + "$eM" + "m"
        }

        # ----------------- Format Live Active Stopwatch (HH:MM:SS) -----------------
        $liveStopwatch = Format-DurationSec $script:SessionState.ActiveSeconds

        # ----------------- Top Row Live Status Rendering -----------------
        $statusSummary = ""
        if ($isAc) {
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
            $TxtTimeIcon.Foreground = $BrushGreen
            
            if ($percentInt -ge 99 -or ($percentInt -ge 79 -and $chargeRate -eq 0)) {
                $TxtRemaining.Text = "Full / Capped"
                $TxtRemaining.ToolTip = "Battery full or capped at health threshold"
            } elseif ($chargeRate -gt 0) {
                $hoursToFull = ($script:FullCapacity - $remaining) / $chargeRate
                if ($hoursToFull -gt 0 -and $hoursToFull -lt 24) {
                    $hrs = [int][math]::Floor($hoursToFull)
                    $mins = [int][math]::Round(($hoursToFull - $hrs) * 60)
                    $TxtRemaining.Text = "$hrs" + "h " + "$mins" + "m to full"
                } else {
                    $TxtRemaining.Text = "Charging"
                }
                $TxtRemaining.ToolTip = "Charging on AC power"
            } else {
                $TxtRemaining.Text = "Plugged in"
                $TxtRemaining.ToolTip = "Connected to AC power"
            }
        } else {
            # Discharging on Battery
            $watts = [math]::Round($dischargeRate / 1000, 1)
            $TxtWattage.Text = "$watts W"
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

            # Top bar displays the LIVE RUNNING STOPWATCH!
            $TxtTimeIcon.Text = $IconClock
            $TxtTimeIcon.Foreground = $BrushSky
            $TxtRemaining.Text = $liveStopwatch
            $TxtRemaining.ToolTip = "Active time on battery (excluding sleep) • Est. $estLeftStr remaining"
        }

        # ----------------- Session Tracker Card Rendering -----------------
        if ($onBattery) {
            # ACTIVE ON BATTERY: Automatically show tracking card!
            if (-not $Settings.Compact) {
                $CardSession.Visibility = [System.Windows.Visibility]::Visible
            }

            $TxtSessionTitleIcon.Text = $IconBat
            $TxtSessionTitle.Text = "Battery Session (Active)"
            $TxtSessionTitle.Foreground = $BrushSky

            # Running Stopwatch (HH:MM:SS)
            $TxtSessionTimer.Text = $liveStopwatch

            # Start info
            $startStr = if ($script:SessionState.StartTimeStr) {
                $script:SessionState.StartTimeStr
            } elseif ($script:SessionState.StartTime) {
                try { [DateTime]::Parse($script:SessionState.StartTime).ToString("h:mm tt") } catch { "" }
            } else { "" }
            
            $TxtSessionStart.Text = "Started at: $($script:SessionState.StartPercent)% $(if ($startStr) { "($startStr)" })"

            # Power Consumed (%)
            $pctDropped = $script:SessionState.StartPercent - $percentInt
            if ($pctDropped -lt 0) { $pctDropped = 0 }
            $TxtSessionUsed.Text = "Used: $pctDropped%"

            # Energy Consumed (Wh)
            $mwhUsed = $script:SessionState.StartMWh - $remaining
            $whUsed = if ($mwhUsed -gt 0) { [math]::Round($mwhUsed / 1000, 1) } else { 0.0 }
            $TxtSessionEnergy.Text = "-$whUsed Wh"

            # Est Remaining
            $TxtSessionEst.Text = "Est: $estLeftStr left"
            $SepSessionEst.Visibility = [System.Windows.Visibility]::Visible
            $TxtSessionEst.Visibility = [System.Windows.Visibility]::Visible
        } else {
            # ON AC POWER (PLUGGED IN)
            if ($script:SessionState.HasLastSession -and (-not $Settings.Compact)) {
                $CardSession.Visibility = [System.Windows.Visibility]::Visible
                $TxtSessionTitleIcon.Text = $IconPlug
                $TxtSessionTitle.Text = "Last Battery Session (Summary)"
                $TxtSessionTitle.Foreground = $BrushGreenLight
                $TxtSessionTimer.Text = $script:SessionState.LastDuration
                $TxtSessionStart.Text = "Started: $($script:SessionState.StartPercent)%"
                $TxtSessionUsed.Text = "Used: $($script:SessionState.LastUsedPercent)%"
                $TxtSessionEnergy.Text = "-$($script:SessionState.LastUsedWh) Wh (Avg $($script:SessionState.LastAvgWatts) W)"
                $SepSessionEst.Visibility = [System.Windows.Visibility]::Collapsed
                $TxtSessionEst.Visibility = [System.Windows.Visibility]::Collapsed
            } else {
                $CardSession.Visibility = [System.Windows.Visibility]::Collapsed
            }
        }

        # ----------------- Update Tray Tooltip (max 63 chars) -----------------
        $trayTip = if ($onBattery) {
            "Bat: $percentInt% ($statusSummary) | $liveStopwatch | CPU: $celsius`°C"
        } else {
            "AC Power ($percentInt%) | CPU: $celsius`°C"
        }
        if ($trayTip.Length -gt 63) { $trayTip = $trayTip.Substring(0, 63) }
        $NotifyIcon.Text = $trayTip

    } catch {
        # Log to debug file if any unexpected error occurs
        try {
            $errLog = Join-Path $ScriptDir "error.log"
            $_.Exception.ToString() | Set-Content -Path $errLog
        } catch {}
    }
}

# Initial state
Set-CompactMode $Settings.Compact
Set-CapacitySlotVisibility $Settings.ShowCapacitySlot
Update-BatteryStats

# Ensure window is explicitly restored and shown
$Window.WindowState = [System.Windows.WindowState]::Normal
$Window.Show()
$Window.Activate()
$Window.Topmost = [bool]$Settings.Topmost

# Timer for real-time polling (1 second interval)
$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromSeconds(1)
$Timer.Add_Tick({ Update-BatteryStats })
$Timer.Start()

# Periodic background save (every 10 seconds)
$SaveTimer = New-Object System.Windows.Threading.DispatcherTimer
$SaveTimer.Interval = [TimeSpan]::FromSeconds(10)
$SaveTimer.Add_Tick({ Save-Settings })
$SaveTimer.Start()

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
