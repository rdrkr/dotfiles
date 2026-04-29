; This script provides Mac-like shortcuts when using a standard Windows keyboard.
; Physical layout: Ctrl, Win (#), Alt (!)
; The Alt key (next to space) will act like the Mac Command key.
; The Win key (middle) will act like the Mac Option key.

SendMode("Input")
SetWorkingDir(A_ScriptDir)

; App switching
; Native Alt+Tab (which uses the physical Alt key next to space) works exactly like Cmd+Tab out of the box! No mapping needed.

; Quit the active app (Alt+Q -> Alt+F4)
!q::Send("!{f4}")

; Insertion point movement (Alt+Arrows -> Home/End)
!Left::
{
    Suspend(true)
    Send("{Home}")
    Suspend(false)
    return
}
!Right::
{
    Suspend(true)
    Send("{End}")
    Suspend(false)
    return
}
!Up::
{
    Suspend(true)
    Send("^{Home}")
    Suspend(false)
    return
}
!Down::
{
    Suspend(true)
    Send("^{End}")
    Suspend(false)
    return
}

; Shift + Alt + Arrows
+!Left::
{
    Suspend(true)
    Send("+{Home}")
    Suspend(false)
    return
}
+!Right::
{
    Suspend(true)
    Send("+{End}")
    Suspend(false)
    return
}
+!Up::
{
    Suspend(true)
    Send("+^{Home}")
    Suspend(false)
    return
}
+!Down::
{
    Suspend(true)
    Send("+^{End}")
    Suspend(false)
    return
}

; Win + Arrows -> Ctrl + Arrows (Jump word)
#Left::
{
    Suspend(true)
    Send("^{Left}")
    Suspend(false)
    return
}
#Right::
{
    Suspend(true)
    Send("^{Right}")
    Suspend(false)
    return
}
+#Left::
{
    Suspend(true)
    Send("+^{Left}")
    Suspend(false)
    return
}
+#Right::
{
    Suspend(true)
    Send("+^{Right}")
    Suspend(false)
    return
}

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
