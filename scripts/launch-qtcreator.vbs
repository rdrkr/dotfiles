Set oShell = CreateObject("WScript.Shell")
oShell.Run "wsl.exe -d Ubuntu -- ~/Qt/Tools/QtCreator/bin/qtcreator", 0, False

