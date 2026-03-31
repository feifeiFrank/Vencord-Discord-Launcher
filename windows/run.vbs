Set shell = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
command = "powershell -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "\run.ps1"" -Silent"
shell.Run command, 0, False
