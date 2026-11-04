$WshShell = New-Object -ComObject WScript.Shell
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$ShortcutPath = Join-Path $DesktopPath "Battery Overlay.lnk"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$TargetScript = Join-Path $ScriptDir "BatteryOverlay.ps1"

$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$TargetScript`""
$Shortcut.WorkingDirectory = $ScriptDir
$Shortcut.WindowStyle = 7 # Minimized console
$Shortcut.Description = "Real-time Battery, Wattage & CPU Temperature Overlay"

if (Test-Path "$env:SystemRoot\System32\batmeter.dll") {
    $Shortcut.IconLocation = "$env:SystemRoot\System32\batmeter.dll,0"
} elseif (Test-Path "$env:SystemRoot\System32\imageres.dll") {
    $Shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,130"
} else {
    $Shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,44"
}

$Shortcut.Save()
Write-Host "Desktop shortcut created: $ShortcutPath"
