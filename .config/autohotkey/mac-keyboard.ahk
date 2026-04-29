; This script provides Mac-like shortcuts when using an Apple/Mac keyboard on Windows.
; Physical layout: Control, Option (sends Alt !), Command (sends Win #)

SendMode("Input")
SetWorkingDir(A_ScriptDir)

; App switching (Cmd+Tab -> Alt+Tab)
LWin & Tab::AltTab

; Quit the active app (Cmd+Q -> Alt+F4)
#q::Send("!{f4}")

; Insertion point movement (Cmd+Arrows -> Home/End)
#Left::
{
    Suspend(true)
    Send("{Home}")
    Suspend(false)
    return
}
#Right::
{
    Suspend(true)
    Send("{End}")
    Suspend(false)
    return
}
#Up::
{
    Suspend(true)
    Send("^{Home}")
    Suspend(false)
    return
}
#Down::
{
    Suspend(true)
    Send("^{End}")
    Suspend(false)
    return
}

; Shift + Cmd + Arrows
+#Left::
{
    Suspend(true)
    Send("+{Home}")
    Suspend(false)
    return
}
+#Right::
{
    Suspend(true)
    Send("+{End}")
    Suspend(false)
    return
}
+#Up::
{
    Suspend(true)
    Send("+^{Home}")
    Suspend(false)
    return
}
+#Down::
{
    Suspend(true)
    Send("+^{End}")
    Suspend(false)
    return
}

; Option + Arrows -> Ctrl + Arrows (Jump word)
!Left::
{
    Suspend(true)
    Send("^{Left}")
    Suspend(false)
    return
}
!Right::
{
    Suspend(true)
    Send("^{Right}")
    Suspend(false)
    return
}
+!Left::
{
    Suspend(true)
    Send("+^{Left}")
    Suspend(false)
    return
}
+!Right::
{
    Suspend(true)
    Send("+^{Right}")
    Suspend(false)
    return
}

; Essential Mac shortcuts (Cmd+C, Cmd+V, etc.) mapped from Win (#)
#c::Send("^c")
#x::Send("^x")
#v::Send("^v")
#a::Send("^a")
#s::Send("^s")
#z::Send("^z")
#f::Send("^f")
#w::Send("^w")
#t::Send("^t")
#d::Send("^d")
