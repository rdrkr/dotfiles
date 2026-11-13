#Requires -Version 5.1
<#
.SYNOPSIS
    Resident watcher: the Dell's screens follow the desk keyboard's Bluetooth link.

.DESCRIPTION
    The Keychron K2 pairs with both the Dell and the MacBook and talks to one of
    them at a time. Whichever machine it is connected to is the one in use, so
    each machine follows its own link:

        keyboard connects to the Dell    -> external  (monitor on, laptop panel off)
        keyboard leaves the Dell         -> internal  (laptop panel on, monitor off)

    The MacBook runs the same rule for its own link (switchbot:
    display/ard_virtual_display.sh). Switching the keyboard from one machine to
    the other therefore hands the monitor over, and the machine it left goes
    back to its own screen.

    Windows signals every device arrival and removal (Win32_DeviceChangeEvent);
    the watcher sleeps on that and only then asks whether the keyboard is
    connected, so it costs nothing while idle and reacts within about a second.
    "Connected" is the paired Bluetooth device's own connection state, the same
    one Settings > Bluetooth shows, not the mere presence of its pairing.

    Only edges act: whatever the keyboard is doing when the watcher starts is
    taken as already applied, so a reload never reshuffles screens arranged by
    hand. A disconnect must last DisconnectGraceSeconds to count, so a Bluetooth
    blip does not flip the screens; a connect counts at once.

    The switch itself is display-topology.ps1 beside this script (Win+P's
    "Second screen only" / "PC screen only"). Started hidden at logon by
    .config/komorebi/komorebic-hotkeys.ahk. Starting it again replaces the
    running instance, so an AHK reload picks up edits to this file.

.PARAMETER KeyboardMatch
    Wildcard pattern for the keyboard's Bluetooth device name.

.PARAMETER DisconnectGraceSeconds
    How long the keyboard must stay disconnected before the laptop panel takes over.

.NOTES
    Log: %LOCALAPPDATA%\keyboard-display-watch.log, trimmed to its last 500 lines
    at every start.
#>
param(
    [string]$KeyboardMatch = '*Keychron*',
    [int]$DisconnectGraceSeconds = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logPath = Join-Path $env:LOCALAPPDATA 'keyboard-display-watch.log'
$topologyScript = Join-Path $PSScriptRoot 'display-topology.ps1'

# DEVPKEY_Device_IsConnected-style flag the Bluetooth stack keeps on a paired
# device node: True while the link is up. The node itself stays present while
# the device is paired, so presence alone says nothing.
$isConnectedKey = '{83DA6326-97A6-4088-9453-A1923F573B29} 15'

# Safety net: re-check this often even without a device event, in case one is
# ever missed (seconds).
$recheckSeconds = 60

<#
.SYNOPSIS
    Appends one timestamped line to the log.
.PARAMETER Message
    The text to log.
#>
function Write-Log([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $logPath -Value $line -Encoding UTF8 } catch {}
}

<#
.SYNOPSIS
    Stops any other instance of this watcher, so the newest one takes over.
#>
function Stop-OtherInstances {
    $self = $PID
    $name = Split-Path -Leaf $PSCommandPath
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
        Where-Object { $_.ProcessId -ne $self -and $_.CommandLine -and $_.CommandLine -like "*$name*" } |
        ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force; Write-Log "replaced instance $($_.ProcessId)" } catch {}
        }
}

<#
.SYNOPSIS
    Tells whether the desk keyboard is connected to this machine right now.
.OUTPUTS
    $true when a paired Bluetooth device matching KeyboardMatch reports its link up.
#>
function Test-KeyboardConnected {
    $devices = @(Get-PnpDevice -Class Bluetooth -FriendlyName $KeyboardMatch -ErrorAction SilentlyContinue)
    foreach ($device in $devices) {
        $flag = Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName $isConnectedKey -ErrorAction SilentlyContinue
        if ($flag -and $flag.Data -eq $true) { return $true }
    }
    return $false
}

<#
.SYNOPSIS
    Switches the screens for a keyboard edge and logs the outcome.
.PARAMETER Connected
    $true for "external only", $false for "laptop panel only".
#>
function Set-DeskLayout([bool]$Connected) {
    $mode = if ($Connected) { 'external' } else { 'internal' }
    try {
        $result = & $topologyScript $mode 2>&1 | Out-String
        $code = $LASTEXITCODE
        Write-Log ("keyboard {0}: {1} -> [{2}] {3}" -f ($(if ($Connected) { 'connected' } else { 'disconnected' })), $mode, $code, $result.Trim())
        return ($code -eq 0)
    } catch {
        Write-Log "keyboard edge: switching to $mode failed: $_"
        return $false
    }
}

# --- Main ---------------------------------------------------------------------

Stop-OtherInstances
if (Test-Path $logPath) {
    try { Get-Content $logPath -Tail 500 | Set-Content $logPath -Encoding UTF8 } catch {}
}

$applied = Test-KeyboardConnected
Write-Log "watcher started (pid $PID, keyboard '$KeyboardMatch' connected: $applied)"

$sourceId = 'keyboard-display-watch'
Register-CimIndicationEvent -ClassName Win32_DeviceChangeEvent -SourceIdentifier $sourceId | Out-Null

# A switch to "external" usually fails at first: the monitor is shared with the
# Mac, and when the keyboard moves over it is still on the Mac's input (or still
# hunting for this one) for several seconds after the Mac lets go, so Windows has
# no external display to switch to yet (Win32 error 31). A failed switch is
# therefore retried every $retrySeconds - and at once on any device event, such
# as the monitor arriving - until it takes, the keyboard leaves again, or
# $retryLimitSeconds pass.
$retrySeconds = 3
$retryLimitSeconds = 90
$retryUntil = $null

try {
    while ($true) {
        $timeout = if ($retryUntil) { $retrySeconds } else { $recheckSeconds }
        $arrived = Wait-Event -SourceIdentifier $sourceId -Timeout $timeout
        # One plug produces a burst of events; take them all and check once.
        if ($arrived) { Get-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue | Remove-Event }

        $connected = Test-KeyboardConnected
        if ($connected -eq $applied) {
            if ($retryUntil) {
                if ((Get-Date) -gt $retryUntil) {
                    Write-Log "gave up switching after $retryLimitSeconds s"
                    $retryUntil = $null
                } elseif (Set-DeskLayout $applied) {
                    $retryUntil = $null
                }
            }
            continue
        }

        if (-not $connected) {
            # Hold off a disconnect for the grace period; a blip comes back in time.
            Start-Sleep -Seconds $DisconnectGraceSeconds
            Get-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue | Remove-Event
            if (Test-KeyboardConnected) { continue }
        }

        # A new edge supersedes any retry still pending for the previous one.
        $applied = $connected
        $retryUntil = $null
        if (-not (Set-DeskLayout $connected)) {
            $retryUntil = (Get-Date).AddSeconds($retryLimitSeconds)
        }
    }
} finally {
    Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
    Write-Log 'watcher stopped'
}
