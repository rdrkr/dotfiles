#Requires AutoHotkey v2.0.2
#SingleInstance Force

if not A_IsAdmin {
	Run "*RunAs " A_AhkPath ' "' A_ScriptFullPath '"'
	ExitApp
}

Komorebic(cmd) {
	RunWait(format("*RunAs komorebic.exe {}", cmd), , "Hide")
}

; State maintained by komorebi-nav-subscriber.ps1 and cached for fast access.
global gNavStateFile := EnvGet("LOCALAPPDATA") "\komorebi-nav-state.txt"
global gNavBits := ""        ; last-known population bitmap ("1"=populated)
global gNavOptCur := -1       ; optimistic current ws index for rapid presses
global gNavOptTime := 0       ; tick of the last optimistic update

; Focus the next/previous *populated* workspace on the focused monitor,
; skipping empty ones. `dir` is 1 for next or -1 for previous. Reads the small
; state file kept fresh by the resident subscriber (see
; komorebi-nav-subscriber.ps1) so the key press never blocks on a query.
; Falls back to a plain cycle until the subscriber has produced state.
CycleWorkspaceSkipEmpty(dir) {
	global gNavStateFile, gNavBits, gNavOptCur, gNavOptTime

	cur := -1
	bits := ""
	try {
		parts := StrSplit(Trim(FileRead(gNavStateFile)), "|")
		if (parts.Length = 2 && parts[2] != "") {
			cur := Integer(parts[1])
			bits := parts[2]
			gNavBits := bits
		}
	}
	if (bits = "")
		bits := gNavBits   ; reuse last good value if the file was mid-write

	if (bits = "") {
		; Subscriber not ready yet: fall back to komorebi's own cycling.
		Run(format("komorebic.exe cycle-workspace {}", dir > 0 ? "next" : "previous"), , "Hide")
		return
	}

	; For rapid repeated presses the file may lag behind; trust our own most
	; recent target for a short window instead of the (stale) file value.
	if (gNavOptCur >= 0 && (A_TickCount - gNavOptTime) < 600)
		cur := gNavOptCur
	if (cur < 0)
		cur := 0

	n := StrLen(bits)
	target := -1
	loop n {
		t := Mod(Mod(cur + dir * A_Index, n) + n, n)
		if (t != cur && SubStr(bits, t + 1, 1) = "1") {
			target := t
			break
		}
	}
	if (target < 0)
		return   ; no other populated workspace

	gNavOptCur := target
	gNavOptTime := A_TickCount
	Run(format("komorebic.exe focus-workspace {}", target), , "Hide")
}

; Disable Win+L lock screen so AHK can intercept it
RegWrite(1, "REG_DWORD", "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\System", "DisableLockWorkstation")

; Start Komorebi
Komorebic("start")

; Start Komorebi Bar or Zebar
; Run("*RunAs komorebi-bar.exe", , "Hide", &BarPID)
; Sleep(1000)
;if !ProcessExist(BarPID) {
	RunWait(A_ComSpec ' /c cd /d "' EnvGet("USERPROFILE") '\.glzr\zebar\gruvbox" && pnpm build', , "Hide")
	Run("*RunAs zebar.exe", , "Hide")
;}

; Start the resident komorebi event subscriber that keeps workspace-population
; state fresh for fast empty-skipping navigation (see CycleWorkspaceSkipEmpty).
Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' A_ScriptDir '\komorebi-nav-subscriber.ps1"', , "Hide")

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

; Exit RDP full screen (Ctrl+Alt+Cmd+B -> Ctrl+Alt+Pause)
^!#b:: Send("^!{Pause}")

; Page navigation (Cmd+Arrows -> Back/Forward)
#Left:: Send("{Browser_Back}")
#Right:: Send("{Browser_Forward}")
#Up:: Send("^{Home}")
#HotIf WinActive("ahk_class CabinetWClass")
#Down:: Send("{Enter}")
#HotIf
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
#HotIf WinActive("ahk_exe ms-teams.exe")
+Enter:: Send("+{Enter}")
#HotIf
+Enter:: Send("^j")
#,:: Send("^,")
#a:: Send("^a")
#b:: Send("^b")
#c:: Send("^c")
#d:: Send("^d")
#e:: Send("^e")
#f:: Send("^f")
#g:: Send("^g")
#h:: Send("^h")
#i:: Send("^i")
#j:: Send("^j")
#k:: Send("^k")
#l:: Send("^l")
#m:: Send("^m")
#n:: Send("^n")
#o:: Send("^o")
#p:: Send("^p")
#r:: Send("^r")
#s:: Send("^s")
#t:: Send("^t")
#u:: Send("^u")
#v:: Send("^v")
#w:: Send("^w")
#x:: Send("^x")
#y:: Send("^y")
#z:: Send("^z")
+#a:: Send("^+a")
+#f:: Send("^+f")
+#m:: Send("#!k")
+#n:: Send("^+n")
+#p:: Send("^+p")
+#s:: Send("^+s")
+#t:: Send("^+t")
#Backspace:: Send("{Delete}")
+#Backspace:: Send("+{Delete}")

; Screenshots (Cmd+Shift+3 / Cmd+Shift+4)
; macOS writes both straight to a file; these map onto the closest Windows
; built-ins, which save into %USERPROFILE%\Pictures\Screenshots rather than the
; desktop:
;   Win+PrintScreen - the whole desktop, file only.
;   Win+Shift+S     - the Snipping Tool crosshair. It always copies to the
;                     clipboard, and writes the file too while Snipping Tool's
;                     "Automatically save screenshots" stays on (the Windows 11
;                     default). Turning that setting off makes this clipboard-only.
; Sending Win+Shift+S here does not re-enter the +#s hotkey above: AHK ignores
; the input its own Send generates.
+#3:: Send("#{PrintScreen}")
+#4:: Send("#+s")

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

; Next/Prev workspace (skipping empty workspaces)
^!Right:: CycleWorkspaceSkipEmpty(1)
^!Left:: CycleWorkspaceSkipEmpty(-1)

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

; Disable mouse zoom
^WheelUp:: return
^WheelDown:: return

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
;	if ProcessExist("komorebi-bar.exe")
;		ProcessClose("komorebi-bar.exe")
	if ProcessExist("zebar.exe")
		ProcessClose("zebar.exe")
	Reload()
}
