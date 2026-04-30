#Requires AutoHotkey v2.0.2
#SingleInstance Force

Komorebic(cmd) {
    RunWait(format("komorebic.exe {}", cmd), , "Hide")
}

; Start Zebar
Run("zebar", , "Hide")

; Focus windows
!^#Left::Komorebic("focus left")
!^#Down::Komorebic("focus down")
!^#Up::Komorebic("focus up")
!^#Right::Komorebic("focus right")

; Workspaces
!1::Komorebic("focus-workspace 0")
!2::Komorebic("focus-workspace 1")
!3::Komorebic("focus-workspace 2")
!4::Komorebic("focus-workspace 3")
!5::Komorebic("focus-workspace 4")
!6::Komorebic("focus-workspace 5")

; Next/Prev workspace
^!Right::Komorebic("cycle-workspace next")
^!Left::Komorebic("cycle-workspace previous")

; Join (Stack)
^!+Left::Komorebic("stack left")
^!+Down::Komorebic("stack down")
^!+Up::Komorebic("stack up")
^!+Right::Komorebic("stack right")
^!+;::Komorebic("unstack")

; Move
^!+#Left::Komorebic("move left")
^!+#Down::Komorebic("move down")
^!+#Up::Komorebic("move up")
^!+#Right::Komorebic("move right")

; Move to workspace
^+1::Komorebic("move-to-workspace 0")
^+2::Komorebic("move-to-workspace 1")
^+3::Komorebic("move-to-workspace 2")
^+4::Komorebic("move-to-workspace 3")
^+5::Komorebic("move-to-workspace 4")
^+6::Komorebic("move-to-workspace 5")

; Resize
^-::Komorebic("resize-axis horizontal decrease")
^=::Komorebic("resize-axis horizontal increase")

; Layout
!/::Komorebic("toggle-float")
!,::Komorebic("flip-layout horizontal")

; Close
!+q::Komorebic("close")

; WM Exit
!+e::Komorebic("stop")

