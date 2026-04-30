; This script provides Mac-like shortcuts when using a standard Windows keyboard.
; Physical layout: Ctrl, Win (#), Alt (!)
; The Alt key (next to space) will act like the Mac Command key.
; The Win key (middle) will act like the Mac Option key.

SendMode("Input")
SetWorkingDir(A_ScriptDir)

; App switching (Win+Tab -> Alt+Tab)
LWin & Tab::AltTab
!Tab::return
+!Tab::return

; Window tabs
!#Left::Send("^+{Tab}")
!#Right::Send("^{Tab}")
+![::Send("^+{Tab}")
+!]::Send("^{Tab}")

; Quit the active app (Alt+Q -> Alt+F4)
!q::Send("!{f4}")

; Page navigation (Alt+Arrows -> Back/Forward)
!Left::Send("{Browser_Back}")
!Right::Send("{Browser_Forward}")
!Up::Send("^{Home}")
!Down::Send("^{End}")

; Shift + Alt + Arrows
+!Left::Send("+{Home}")
+!Right::Send("+{End}")
+!Up::Send("+^{Home}")
+!Down::Send("+^{End}")

; Win + Arrows -> Ctrl + Arrows (Jump word)
#Left::Send("^{Left}")
#Right::Send("^{Right}")
+#Left::Send("+^{Left}")
+#Right::Send("+^{Right}")

; Windows Terminal specific Overrides
#HotIf WinActive("ahk_exe WindowsTerminal.exe")
!Enter::Send("^j")
!c::Send("^+c")
!v::Send("^+v")
!x::Send("^+x")
!t::Send("^+t")
!w::Send("^+w")
!f::Send("^+f")
!n::Send("^+n")
#HotIf

; Essential Mac shortcuts (Cmd+C, Cmd+V, etc.) mapped from Alt (!)
!c::Send("^c")
!x::Send("^x")
!v::Send("^v")
!a::Send("^a")
!s::Send("^s")
!z::Send("^z")
!f::Send("^f")
!w::Send("^w")
!t::Send("^t")
!d::Send("^d")
!n::Send("^n")
