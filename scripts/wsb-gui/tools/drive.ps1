<#
.SYNOPSIS
  Guest-side GUI driver for wsb-gui: runs inside Windows Sandbox (Windows PowerShell 5.1) and acts on the
  windows of one process, so every click and keystroke stays inside the sandbox session.
.DESCRIPTION
  wsb exec returns no process output, so everything this script would print goes to -Result instead and the
  host wrapper (wsb-gui.ps1 -Do) prints that file. Coordinates are relative to the chosen window's top-left,
  the same pixels as its screenshot.
.PARAMETER Action
  list | shot | click | dclick | pclick | keys | wheel | move | place | corner | launch | cursor
  list   - visible windows of the process, largest first ("index 'title' x,y wxh").
  shot   - PNG of the window (-Out), or of the whole screen with -Screen.
  click  - real mouse click (SetCursorPos + mouse_event), raising the window first.
  place  - moves AND resizes every window of the process to -X,-Y with size -Width x -Height (apps that size themselves
           to the screen get the same layout as on the host, so recorded coordinates stay valid).
  pclick - click posted to the deepest child under the point (no z-order needed); -Text bm adds BM_CLICK.
  corner - prints EXIT when the window's top-right button is a yellow X (MAGNET Field home screen), else OTHER.
  launch - starts -Text as a process (working directory = its folder) and prints its PID.
  cursor - prints the cursor position (proves input never left the sandbox when compared with the host's).
.PARAMETER ExeLike
  Substring of the target process's executable path (e.g. C:\mf\dev\); empty = no process filter.
.PARAMETER Proc
  Process name filter (without .exe); default mf.
.PARAMETER Title
  Exact title of the window to act on; empty = the foreground window of the process, else the last titled one.
.PARAMETER X
  X relative to the window's left edge.
.PARAMETER Y
  Y relative to the window's top edge.
.PARAMETER Width
  With place: window width.
.PARAMETER Height
  With place: window height.
.PARAMETER Text
  SendKeys string (keys), wheel delta (wheel), 'bm' (pclick) or the executable to start (launch).
.PARAMETER ArgList
  With launch: the argument string for the started process.
.PARAMETER Out
  PNG path written after the action (optional).
.PARAMETER Screen
  With shot: capture the whole virtual screen instead of one window.
.PARAMETER Result
  File that receives everything the script reports; the host prints it.
#>
param([string]$Action = "list", [string]$ExeLike = "", [string]$Proc = "mf", [string]$Title = "", [int]$X = 0, [int]$Y = 0, [int]$Width = 0, [int]$Height = 0,
      [string]$Text = "", [string]$ArgList = "", [string]$Out = "", [switch]$Screen, [string]$Result = "")

$script:lines = New-Object System.Collections.ArrayList

<#
.SYNOPSIS
  Records one line of output for the host.
.PARAMETER s
  The line.
#>
function Say([string]$s) { [void]$script:lines.Add($s) }

<#
.SYNOPSIS
  Writes the recorded lines to -Result (or stdout when run by hand) and exits with the given code.
.PARAMETER code
  Process exit code.
#>
function Finish([int]$code) {
  if ($Result) { $dir = Split-Path $Result; if ($dir) { New-Item -ItemType Directory -Force $dir | Out-Null }; Set-Content -Path $Result -Value ($script:lines -join "`r`n") -Encoding UTF8 }
  else { $script:lines | ForEach-Object { Write-Output $_ } }
  exit $code
}

try {
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class W {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int d, IntPtr e);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, IntPtr e);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern IntPtr ChildWindowFromPointEx(IntPtr h, POINT p, uint flags);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  public struct POINT { public int X, Y; }
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  public struct RECT { public int L, T, R, B; }
}
"@
[W]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

<#
.SYNOPSIS
  Saves a PNG of a screen rectangle.
.PARAMETER l
  Left edge. .PARAMETER t Top edge. .PARAMETER w Width. .PARAMETER h Height. .PARAMETER path Output file.
#>
function SaveShot([int]$l, [int]$t, [int]$w, [int]$h, [string]$path) {
  $dir = Split-Path $path; if ($dir) { New-Item -ItemType Directory -Force $dir | Out-Null }
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($l, $t, 0, 0, $bmp.Size)
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
}

if ($Action -eq "launch") {
  $sp = @{ FilePath = $Text; WorkingDirectory = (Split-Path $Text); PassThru = $true }; if ($ArgList) { $sp.ArgumentList = $ArgList }
  $p = Start-Process @sp
  Say "launched $Text pid $($p.Id)"; Finish 0
}
if ($Action -eq "cursor") { $pt = New-Object W+POINT; [W]::GetCursorPos([ref]$pt) | Out-Null; Say "cursor $($pt.X),$($pt.Y)"; Finish 0 }
if ($Action -eq "shot" -and $Screen) {
  $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
  SaveShot $vs.Left $vs.Top $vs.Width $vs.Height $Out; Say "screen $($vs.Width)x$($vs.Height) -> $Out"; Finish 0
}

$procs = @(Get-CimInstance Win32_Process -Filter "Name='$Proc.exe'" | Where-Object { -not $ExeLike -or ($_.ExecutablePath -and $_.ExecutablePath.Contains($ExeLike)) })
if ($procs.Count -eq 0) { Say "NO PROCESS ($Proc $ExeLike)"; Finish 2 }
$pids = @($procs | ForEach-Object { [uint32]$_.ProcessId })

$script:wins = New-Object System.Collections.ArrayList
$cb = [W+EnumProc]{ param($h, $p)
  $wpid = [uint32]0; [W]::GetWindowThreadProcessId($h, [ref]$wpid) | Out-Null
  if ($pids -contains $wpid -and [W]::IsWindowVisible($h)) {
    $r = New-Object W+RECT; [W]::GetWindowRect($h, [ref]$r) | Out-Null
    $sb = New-Object System.Text.StringBuilder 256; [W]::GetWindowText($h, $sb, 256) | Out-Null
    [void]$script:wins.Add([pscustomobject]@{ H = $h; R = $r; Area = ($r.R - $r.L) * ($r.B - $r.T); Title = $sb.ToString() })
  }
  return $true }
[W]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
# EnumWindows walks the z-order top-down: keep that order so index 0 is the frontmost window
$sorted = @($script:wins | Where-Object { $_.Area -gt 0 })

if ($Action -eq "list") { $i = 0; foreach ($w in $sorted) { Say "$i '$($w.Title)' $($w.R.L),$($w.R.T) $($w.R.R - $w.R.L)x$($w.R.B - $w.R.T)"; $i++ }; Finish 0 }
if ($Action -eq "place") { foreach ($w in $sorted) { [W]::SetWindowPos($w.H, [IntPtr]::Zero, $X, $Y, $Width, $Height, 0x14) | Out-Null }; Say "placed $($sorted.Count) window(s) at $X,$Y ${Width}x$Height"; Finish 0 }
if ($Action -eq "move") { foreach ($w in $sorted) { [W]::SetWindowPos($w.H, [IntPtr]::Zero, $X, $Y, 0, 0, 0x15) | Out-Null }; Say "moved $($sorted.Count) window(s) to $X,$Y"; Finish 0 }
if ($sorted.Count -eq 0) { Say "NO WINDOW"; Finish 3 }

if ($Title) { $byTitle = @($sorted | Where-Object { $_.Title -eq $Title }); if ($byTitle.Count -eq 0) { Say "NO WINDOW '$Title'"; Finish 3 }; $win = $byTitle[0] }
else {
  $fg = [W]::GetForegroundWindow(); $front = @($sorted | Where-Object { $_.H -eq $fg })
  $win = if ($front.Count -gt 0) { $front[0] } else { $sorted[0] }
}

<#
.SYNOPSIS
  Brings the target window to the front when another window owns the foreground.
#>
function Focus() {
  if ([W]::GetForegroundWindow() -ne $win.H) {
    [W]::SetWindowPos($win.H, [IntPtr](-1), 0, 0, 0, 0, 0x3) | Out-Null; [W]::SetWindowPos($win.H, [IntPtr](-2), 0, 0, 0, 0, 0x3) | Out-Null
    [W]::keybd_event(0x12, 0, 0, [IntPtr]::Zero); [W]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
    [W]::SetForegroundWindow($win.H) | Out-Null; Start-Sleep -Milliseconds 300
  }
}

switch ($Action) {
  "click" { Focus; [W]::SetCursorPos($win.R.L + $X, $win.R.T + $Y) | Out-Null; Start-Sleep -Milliseconds 80; [W]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 60; [W]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero) }
  "dclick" { Focus; [W]::SetCursorPos($win.R.L + $X, $win.R.T + $Y) | Out-Null; for ($k = 0; $k -lt 2; $k++) { [W]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero); [W]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 60 } }
  "wheel" { Focus; [W]::SetCursorPos($win.R.L + $X, $win.R.T + $Y) | Out-Null; [W]::mouse_event(0x800, 0, 0, [int]$Text, [IntPtr]::Zero) }
  "keys" { Focus; [System.Windows.Forms.SendKeys]::SendWait($Text) }
  "pclick" {
    # post the click to the deepest visible child under the point: works whatever covers the window
    $target = $win.H
    while ($true) {
      $pt = New-Object W+POINT; $pt.X = $win.R.L + $X; $pt.Y = $win.R.T + $Y
      [W]::ScreenToClient($target, [ref]$pt) | Out-Null
      $child = [W]::ChildWindowFromPointEx($target, $pt, 0x5)
      if ($child -eq [IntPtr]::Zero -or $child -eq $target) { break }
      $target = $child
    }
    $pt = New-Object W+POINT; $pt.X = $win.R.L + $X; $pt.Y = $win.R.T + $Y
    [W]::ScreenToClient($target, [ref]$pt) | Out-Null
    $lp = [IntPtr](($pt.Y -shl 16) -bor ($pt.X -band 0xFFFF))
    [W]::PostMessage($target, 0x200, [IntPtr]0, $lp) | Out-Null
    [W]::PostMessage($target, 0x201, [IntPtr]1, $lp) | Out-Null
    Start-Sleep -Milliseconds 60
    [W]::PostMessage($target, 0x202, [IntPtr]0, $lp) | Out-Null
    if ($Text -eq "bm") { [W]::PostMessage($target, 0xF5, [IntPtr]0, [IntPtr]0) | Out-Null }
  }
  "corner" {
    $path = Join-Path $env:TEMP "wsbgui-corner.png"; $w2 = $win.R.R - $win.R.L
    SaveShot $win.R.L $win.R.T $w2 90 $path
    $bmp = [System.Drawing.Bitmap]::FromFile($path); $yellow = 0
    for ($x = [Math]::Max(0, $w2 - 120); $x -lt $w2 - 10; $x += 2) { for ($y = 5; $y -lt 85; $y += 2) {
      $c = $bmp.GetPixel($x, $y); if ($c.R -gt 200 -and $c.G -gt 140 -and $c.G -lt 200 -and $c.B -lt 90) { $yellow++ } } }
    $bmp.Dispose(); Say $(if ($yellow -gt 100) { "EXIT $yellow" } else { "OTHER $yellow" })
  }
}
if ($Out) { Start-Sleep -Milliseconds 900; SaveShot $win.R.L $win.R.T ($win.R.R - $win.R.L) ($win.R.B - $win.R.T) $Out }
Say "OK '$($win.Title)' $($win.R.L),$($win.R.T) $($win.R.R - $win.R.L)x$($win.R.B - $win.R.T)"
Finish 0
} catch { Say "ERROR $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber)"; Finish 9 }
