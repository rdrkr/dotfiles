; This script provides Mac-like shortcuts when using an Apple/Mac keyboard on Windows.
; Physical layout: Control, Option (sends Alt !), Command (sends Win #)

SendMode("Input")
SetWorkingDir(A_ScriptDir)

; App switching (Cmd+Tab -> Alt+Tab)
LWin & Tab::AltTab
!Tab:: return
+!Tab:: return

; Window tabs
#!Left:: Send("^+{Tab}")
#!Right:: Send("^{Tab}")
+#[:: Send("^+{Tab}")
+#]:: Send("^{Tab}")

; Quit the active app (Cmd+Q -> Alt+F4)
#q:: Send("!{f4}")

; Page navigation (Cmd+Arrows -> Back/Forward)
#Left:: Send("{Browser_Back}")
#Right:: Send("{Browser_Forward}")
#Up:: Send("^{Home}")
#Down:: Send("^{End}")

; Shift + Cmd + Arrows
+#Left:: Send("+{Home}")
+#Right:: Send("+{End}")
+#Up:: Send("+^{Home}")
+#Down:: Send("+^{End}")

; Option + Arrows -> Ctrl + Arrows (Jump word)
!Left:: Send("^{Left}")
!Right:: Send("^{Right}")
!Up:: Send("^{Up}")
!Down:: Send("^{Down}")
+!Left:: Send("+^{Left}")
+!Right:: Send("+^{Right}")
+!Up:: Send("+^{Up}")
+!Down:: Send("+^{Down}")

^Left:: Send("!#^{Left}")
^Right:: Send("!#^{Right}")
^Up:: Send("!#^{Up}")
^Down:: Send("!#^{Down}")
+^Left:: Send("+!#^{Left}")
+^Right:: Send("+!#^{Right}")
+^Up:: Send("+!#^{Up}")
+^Down:: Send("+!#^{Down}")

; Essential Mac shortcuts (Cmd+C, Cmd+V, etc.) mapped from Win (#)
!Enter:: Send("^j")
#c:: Send("^c")
#x:: Send("^x")
#v:: Send("^v")
#a:: Send("^a")
#s:: Send("^s")
#z:: Send("^z")
#f:: Send("^f")
#w:: Send("^w")
#t:: Send("^t")
#d:: Send("^d")
#n:: Send("+^n")
