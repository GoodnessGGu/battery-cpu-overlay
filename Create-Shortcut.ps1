$WshShell = New-Object -ComObject WScript.Shell
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$ShortcutPath = Join-Path $DesktopPath "Battery Overlay.lnk"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$TargetVbs = Join-Path $ScriptDir "Launch.vbs"
$TargetPs1 = Join-Path $ScriptDir "BatteryOverlay.ps1"

$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
if (Test-Path $TargetVbs) {
    # Launch completely silently via wscript (no console flash)
    $Shortcut.TargetPath = "wscript.exe"
    $Shortcut.Arguments = "`"$TargetVbs`""
} else {
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$TargetPs1`""
}
$Shortcut.WorkingDirectory = $ScriptDir
$Shortcut.WindowStyle = 1 # Normal window
$Shortcut.Description = "Real-time Battery, Wattage & CPU Temperature Overlay"

if (Test-Path "$env:SystemRoot\System32\batmeter.dll") {
    $Shortcut.IconLocation = "$env:SystemRoot\System32\batmeter.dll,0"
} elseif (Test-Path "$env:SystemRoot\System32\imageres.dll") {
    $Shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,130"
} else {
    $Shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,44"
}

$Shortcut.Save()
Write-Host "Desktop shortcut created successfully: $ShortcutPath"
