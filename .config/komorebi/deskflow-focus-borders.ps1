# Resident Deskflow-aware komorebi border toggle.
#
# The Dell (Deskflow server) and the MacBook (Deskflow client) each draw a
# border around their own focused window, so with both screens lit there is no
# single "this is where my keyboard goes" indicator. This script makes the Dell
# side follow Deskflow: komorebi's borders are shown only while Deskflow input
# is on this machine, and hidden while it is on the Mac (whose JankyBorders is
# toggled the same way by .config/borders/deskflow-focus-borders.sh).
#
# Deskflow has no hooks, but deskflow-core logs every switch, e.g.
#   switch from "eu-poc-6z3ygk4" to "rdrkr-mbp-m1" at 2559,720
# This script tails that log (Deskflow must have file logging on; see
# .config/deskflow/deskflow-server.conf) and runs `komorebic border
# enable|disable` when input lands on / leaves this machine.
#
# The script is single-instance (global mutex) and self-terminates once
# komorebi is no longer running, so it is safe for the AHK script to (re)launch
# it on every start/reload. Borders are re-enabled whenever it starts or exits
# normally so they are never left hidden by accident.

$ErrorActionPreference = 'Stop'

$deskflowConf = Join-Path $env:APPDATA 'Deskflow\Deskflow.conf'
$defaultLog   = Join-Path $env:LOCALAPPDATA 'Deskflow\deskflow.log'
$pollMs       = 150

# Same wait-then-take-over single-instance scheme as komorebi-nav-subscriber.ps1.
$mutex = New-Object System.Threading.Mutex($false, 'Global\komorebi-deskflow-focus-borders')
$acquired = $false
try {
    $acquired = $mutex.WaitOne(5000)
} catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
}
if (-not $acquired) { return }

<#
.SYNOPSIS
Reads one value from an INI-style section of Deskflow.conf.
.PARAMETER Section
Section name without brackets, e.g. 'core'.
.PARAMETER Key
Key name within the section, e.g. 'computerName'.
.OUTPUTS
The value as a string, or $null when the file, section or key is missing.
#>
function Get-DeskflowSetting([string]$Section, [string]$Key) {
    if (-not (Test-Path $deskflowConf)) { return $null }
    $inSection = $false
    foreach ($line in Get-Content $deskflowConf) {
        if ($line -match '^\s*\[(.+)\]\s*$') {
            $inSection = ($Matches[1] -eq $Section)
        } elseif ($inSection -and $line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*)$") {
            return $Matches[1].Trim()
        }
    }
    return $null
}

# This machine's Deskflow name (what appears in `switch ... to "<name>"`).
$selfName = Get-DeskflowSetting 'core' 'computerName'
if (-not $selfName) { $selfName = $env:COMPUTERNAME }

# Log file written by deskflow-core ([log] file=...), with our default path.
$logPath = Get-DeskflowSetting 'log' 'file'
if (-not $logPath) { $logPath = $defaultLog }
$logPath = [System.IO.Path]::GetFullPath($logPath)

# Last border state applied: $true shown, $false hidden, $null not yet known.
$script:bordersOn = $null

<#
.SYNOPSIS
Shows or hides komorebi's window borders, skipping the call when unchanged.
.PARAMETER On
$true to enable borders, $false to disable them.
.PARAMETER Force
Apply even if the cached state says it is already in effect.
#>
function Set-Borders([bool]$On, [switch]$Force) {
    if (-not $Force -and $script:bordersOn -eq $On) { return }
    $state = if ($On) { 'enable' } else { 'disable' }
    try { & komorebic.exe border $state | Out-Null } catch {}
    $script:bordersOn = $On
}

<#
.SYNOPSIS
Updates the border state from one Deskflow log line.
.PARAMETER Line
A single line of deskflow-core log output.
#>
function Invoke-LogLine([string]$Line) {
    if ($Line -match 'switch from "[^"]*" to "([^"]*)"') {
        Set-Borders ($Matches[1] -ieq $selfName)
    } elseif ($Line -match 'client "[^"]*" has disconnected' -or
              $Line -match 'started server, waiting for clients') {
        # A client dropping (or the server restarting) puts input back here.
        Set-Borders $true
    }
}

<#
.SYNOPSIS
Returns the current size of the log file, or -1 if it does not exist.
#>
function Get-LogLength {
    $info = New-Object System.IO.FileInfo $logPath
    if ($info.Exists) { return $info.Length }
    return -1
}

<#
.SYNOPSIS
Reads the bytes appended to the log since offset From, up to offset To.
.DESCRIPTION
The file is opened only for the duration of the read, with full sharing, so
Deskflow can keep appending to it and rotate (rename) it at any time.
.OUTPUTS
The new text, decoded as UTF-8.
#>
function Read-LogRange([long]$From, [long]$To) {
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $fs = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
    try {
        $fs.Position = $From
        $count = [int]($To - $From)
        $buf = New-Object byte[] $count
        $read = 0
        while ($read -lt $count) {
            $n = $fs.Read($buf, $read, $count - $read)
            if ($n -le 0) { break }
            $read += $n
        }
        return [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
    } finally {
        $fs.Dispose()
    }
}

# Input is on the server when this starts (login / AHK reload), so start shown.
Set-Borders $true -Force

try {
    # Start at the end: only switches from now on matter.
    $pos = [math]::Max(0, (Get-LogLength))
    $acc = ''
    $lastAliveCheck = [DateTime]::MinValue

    while ($true) {
        # Stop once komorebi has gone away (e.g. WM exit), with a short grace
        # period to ride out restarts.
        if (([DateTime]::UtcNow - $lastAliveCheck).TotalSeconds -ge 2) {
            $lastAliveCheck = [DateTime]::UtcNow
            if (-not (Get-Process komorebi -ErrorAction SilentlyContinue)) {
                Start-Sleep -Seconds 2
                if (-not (Get-Process komorebi -ErrorAction SilentlyContinue)) { break }
                # komorebi restarted with its config's borders on; re-apply
                # whatever Deskflow last told us.
                Set-Borders $script:bordersOn -Force
            }
        }

        $len = Get-LogLength
        if ($len -lt 0) {
            # No log yet (logging just turned on, or mid-rotation).
            $pos = 0
            Start-Sleep -Milliseconds 500
            continue
        }
        if ($len -lt $pos) {
            # Truncated or rotated to a fresh file: read it from the start.
            $pos = 0
            $acc = ''
        }
        if ($len -eq $pos) {
            Start-Sleep -Milliseconds $pollMs
            continue
        }

        try {
            $acc += Read-LogRange $pos $len
            $pos = $len
        } catch {
            Start-Sleep -Milliseconds $pollMs
            continue
        }

        # Handle complete lines; keep a trailing partial line for next time.
        $lines = $acc -split "`r?`n"
        $acc = $lines[-1]
        for ($i = 0; $i -lt $lines.Count - 1; $i++) {
            if ($lines[$i]) { Invoke-LogLine $lines[$i] }
        }
    }
} finally {
    Set-Borders $true -Force
    $mutex.ReleaseMutex()
}
