#Requires AutoHotkey v2.0.2
#SingleInstance Force

if not A_IsAdmin {
	Run "*RunAs " A_AhkPath ' "' A_ScriptFullPath '"'
	ExitApp
}

Komorebic(cmd) {
	RunWait(format("*RunAs komorebic.exe {}", cmd), , "Hide")
}

; Start Komorebi
Komorebic("start")

; Start Komorebi Bar or Zebar
Run("*RunAs komorebi-bar.exe", , "Hide", &BarPID)
Sleep(1000)
if !ProcessExist(BarPID) {
	RunWait(A_ComSpec ' /c cd /d "' EnvGet("USERPROFILE") '\.glzr\zebar\gruvbox" && pnpm build', , "Hide")
	Run("*RunAs zebar.exe", , "Hide")
}

; Language switching (Alt+Space -> Ctrl+Shift)
!Space:: Send("{Ctrl Down}{Shift}{Ctrl Up}")

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

^Left:: Komorebic("focus left")
^Right:: Komorebic("focus right")
^Up:: Komorebic("focus up")
^Down:: Komorebic("focus down")
+^Left:: Komorebic("move left")
+^Right:: Komorebic("move right")
+^Up:: Komorebic("move up")
+^Down:: Komorebic("move down")

; Essential Mac shortcuts (Cmd+C, Cmd+V, etc.) mapped from Win (#)
+Enter:: Send("^j")
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
#n:: Send("^n")

; Focus windows
!^#Left:: Komorebic("focus left")
!^#Down:: Komorebic("focus down")
!^#Up:: Komorebic("focus up")
!^#Right:: Komorebic("focus right")

; Workspaces
!1:: Komorebic("focus-workspace 0")
!2:: Komorebic("focus-workspace 1")
!3:: Komorebic("focus-workspace 2")
!4:: Komorebic("focus-workspace 3")
!5:: Komorebic("focus-workspace 4")
!6:: Komorebic("focus-workspace 5")

; Next/Prev workspace
^!Right:: Komorebic("cycle-workspace next")
^!Left:: Komorebic("cycle-workspace previous")

; Move
^!+#Left:: Komorebic("move left")
^!+#Down:: Komorebic("move down")
^!+#Up:: Komorebic("move up")
^!+#Right:: Komorebic("move right")

; Move to workspace
^+1:: Komorebic("move-to-workspace 0")
^+2:: Komorebic("move-to-workspace 1")
^+3:: Komorebic("move-to-workspace 2")
^+4:: Komorebic("move-to-workspace 3")
^+5:: Komorebic("move-to-workspace 4")
^+6:: Komorebic("move-to-workspace 5")

; Resize
^-:: Komorebic("resize-axis horizontal decrease")
^=:: Komorebic("resize-axis horizontal increase")
+^-:: Komorebic("resize-axis vertical decrease")
+^=:: Komorebic("resize-axis vertical increase")

; Layout
!/:: Komorebic("toggle-float")
!,:: Komorebic("flip-layout horizontal")

; Close
!+q:: Komorebic("close")

; WM Exit
!+e:: {
	Komorebic("stop")
	if ProcessExist("komorebi-bar.exe")
		ProcessClose("komorebi-bar.exe")
	if ProcessExist("zebar.exe")
		ProcessClose("zebar.exe")
}

; Restart WM and Bars (Stop and start itself)
!+;:: {
	Komorebic("stop")
	if ProcessExist("komorebi-bar.exe")
		ProcessClose("komorebi-bar.exe")
	if ProcessExist("zebar.exe")
		ProcessClose("zebar.exe")
	Reload()
}
