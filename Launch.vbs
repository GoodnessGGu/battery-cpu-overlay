Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = fso.BuildPath(scriptDir, "BatteryOverlay.ps1")
WshShell.Run "powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File """ & psScript & """", 0, False
