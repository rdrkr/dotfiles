Set objShell = WScript.CreateObject("WScript.Shell")
Dim args
args = ""
For i = 0 to WScript.Arguments.Count - 1
    args = args & """" & WScript.Arguments(i) & """ "
Next
objShell.Run Trim(args), 0, False