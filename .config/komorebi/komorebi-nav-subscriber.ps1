# Resident komorebi event subscriber.
#
# Subscribes to komorebi's notification stream over a named pipe and keeps a
# tiny state file up to date describing, for the *focused* monitor, which
# workspaces are populated and which one is currently focused. The AHK hotkey
# script reads that file to navigate between populated workspaces instantly,
# without spawning `komorebic state` (or PowerShell) on every key press.
#
# State file format (single ASCII line, no newline):
#   <focusedWorkspaceIndex>|<populationBits>
# e.g. "1|110101" -> 6 workspaces, ws0/1/3/5 populated, ws2/4 empty, focused=1.
#
# A workspace is "populated" when it has any tiling containers, floating
# windows, a monocle container, or a maximized window (matching the zebar bar).
#
# The script is single-instance (global mutex) and self-terminates once
# komorebi is no longer running, so it is safe for the AHK script to (re)launch
# it on every start/reload.

$ErrorActionPreference = 'Stop'

$pipeName  = 'komorebi-ahk-nav'
$stateFile = Join-Path $env:LOCALAPPDATA 'komorebi-nav-state.txt'
$tmpFile   = "$stateFile.tmp"

# Ensure only one subscriber runs at a time. Wait briefly (rather than bailing
# immediately) so that on an AHK reload this fresh instance can take over once
# the previous one releases the mutex, avoiding a window with no subscriber. An
# AbandonedMutexException means a previous instance died without releasing it;
# ownership transfers to us, so treat it as acquired.
$mutex = New-Object System.Threading.Mutex($false, 'Global\komorebi-ahk-nav-subscriber')
$acquired = $false
try {
    $acquired = $mutex.WaitOne(5000)
} catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
}
if (-not $acquired) { return }

# Computes the focused monitor's "focused|bits" descriptor from a komorebi
# state object and writes it atomically to the state file.
function Write-NavState($state) {
    $mons    = $state.monitors
    $mon     = $mons.elements[$mons.focused]
    $focused = $mon.workspaces.focused
    $bits    = New-Object System.Text.StringBuilder
    foreach ($w in $mon.workspaces.elements) {
        $populated = (@($w.containers.elements).Count -gt 0) -or
                     (@($w.floating_windows.elements).Count -gt 0) -or
                     ($null -ne $w.monocle_container) -or
                     ($null -ne $w.maximized_window)
        [void]$bits.Append($(if ($populated) { '1' } else { '0' }))
    }
    Set-Content -Path $tmpFile -Value "$focused|$($bits.ToString())" -Encoding Ascii -NoNewline
    Move-Item -Path $tmpFile -Destination $stateFile -Force
}

# Frames complete top-level JSON objects out of a byte-stream accumulator.
# komorebi writes one notification per message with no delimiter, and the
# In-direction server pipe cannot be switched to message read mode, so we scan
# for balanced braces (string/escape aware) to split/join reads reliably.
# Returns a two-element array: @(<list of complete object strings>, <remainder>).
function Get-CompleteJsonObjects([string]$s) {
    $objs   = New-Object System.Collections.Generic.List[string]
    $depth  = 0
    $inStr  = $false
    $esc    = $false
    $start  = -1
    for ($i = 0; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($inStr) {
            if ($esc)            { $esc = $false }
            elseif ($ch -eq '\') { $esc = $true }
            elseif ($ch -eq '"') { $inStr = $false }
            continue
        }
        if ($ch -eq '"')      { $inStr = $true; continue }
        if ($ch -eq '{')      { if ($depth -eq 0) { $start = $i }; $depth++ }
        elseif ($ch -eq '}')  {
            $depth--
            if ($depth -eq 0 -and $start -ge 0) {
                $objs.Add($s.Substring($start, $i - $start + 1))
                $start = -1
            }
        }
    }
    $remainder = if ($start -ge 0) { $s.Substring($start) } else { '' }
    return ,@($objs, $remainder)
}

# Seed the file with the current state so navigation works before the first
# event arrives.
try { Write-NavState (komorebic state | ConvertFrom-Json) } catch {}

try {
    while ($true) {
        # Stop once komorebi has gone away (e.g. WM exit), with a short grace
        # period to ride out restarts.
        if (-not (Get-Process komorebi -ErrorAction SilentlyContinue)) {
            Start-Sleep -Seconds 2
            if (-not (Get-Process komorebi -ErrorAction SilentlyContinue)) { break }
            continue
        }

        $server = $null
        try {
            # Byte-mode pipe with a large buffer; message read mode is not
            # permitted on an In-direction server pipe, so framing is handled by
            # Get-CompleteJsonObjects.
            $server = New-Object System.IO.Pipes.NamedPipeServerStream(
                $pipeName,
                [System.IO.Pipes.PipeDirection]::In,
                1,
                [System.IO.Pipes.PipeTransmissionMode]::Byte,
                [System.IO.Pipes.PipeOptions]::None,
                1048576,
                1048576)

            # Ask komorebi to connect and stream notifications to our pipe.
            Start-Process -WindowStyle Hidden komorebic -ArgumentList 'subscribe-pipe', $pipeName
            $connect = $server.WaitForConnectionAsync()
            while (-not $connect.Wait(2000)) {
                if (-not (Get-Process komorebi -ErrorAction SilentlyContinue)) { return }
                # komorebi may have (re)started; re-issue the subscription.
                try { Start-Process -WindowStyle Hidden komorebic -ArgumentList 'subscribe-pipe', $pipeName } catch {}
            }

            $buf = New-Object byte[] 1048576
            $acc = ''
            while ($true) {
                $n = $server.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }   # komorebi disconnected
                $acc += [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
                $framed = Get-CompleteJsonObjects $acc
                foreach ($obj in $framed[0]) {
                    try {
                        $note = $obj | ConvertFrom-Json
                        if ($note.state) { Write-NavState $note.state }
                    } catch {}
                }
                $acc = $framed[1]
            }
        } catch {
            Start-Sleep -Milliseconds 1000
        } finally {
            if ($server) { $server.Dispose() }
        }
    }
} finally {
    $mutex.ReleaseMutex()
}
