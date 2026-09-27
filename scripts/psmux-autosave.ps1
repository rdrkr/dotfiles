#Requires -Version 5.1
<#
.SYNOPSIS
    Saves every psmux session with psmux-resurrect on a timer, from a single
    long-lived process per user.
.DESCRIPTION
    The tmux side gets periodic saves from tmux-continuum. Its psmux port
    (psmux-continuum) starts its save loop with `run-shell "pwsh ..."` from the
    client-attached hook, which is the server spawning a process - the call
    that fails with "The handle is invalid" on psmux servers without a console
    of their own (see ~/.psmux.conf, which unsets client-attached for exactly
    that reason). So the loop lives here instead and is started by profile.ps1
    from a pane shell, like psmux-stats-daemon.ps1.

    psmux runs one server per session, so profile.ps1 may try to start this
    from many panes; a machine-wide named mutex keeps one loop for the user,
    and every save covers every session. The loop ends once no psmux server is
    left, and the next pane shell starts a new one.

    A session closed on purpose drops out of the save at the next tick. The
    save keeps its previous contents when no session is left at all (psmux
    cannot tell that apart from a server that went down), so closing every
    session does not clear what the next boot restores.
.PARAMETER IntervalMinutes
    Minutes between saves. psmux-resurrect skips the write when nothing
    changed, so a short interval costs little.
.PARAMETER Worker
    Internal. Set on the re-launched copy that runs the loop; a bare run only
    detaches that copy and returns.
.EXAMPLE
    pwsh -NoProfile -File psmux-autosave.ps1
    Detaches a worker. Run by hand to restart saving after killing it.
.NOTES
    Requires psmux-resurrect (installed by scripts/install-psmux-plugins.ps1).
    profile.ps1 starts it and restores the last save once per boot.
#>

param(
    [int]$IntervalMinutes = 5,
    [switch]$Worker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

## Name of the machine-wide mutex that keeps a single loop per user. profile.ps1
## checks the same name before starting one.
$script:MUTEX_NAME = 'Local\psmux-autosave'

## Seconds between checks that a psmux server is still up, so the loop exits
## soon after the last session goes instead of at the next save.
$script:LIVENESS_SECONDS = 10

function Get-PsmuxBin {
    <#
    .SYNOPSIS
        Resolves the psmux executable to call.
    .OUTPUTS
        System.String. Full path to psmux, or the bare name when it is not on
        PATH.
    #>
    $cmd = Get-Command psmux -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return 'psmux'
}

function Get-PwshPath {
    <#
    .SYNOPSIS
        Returns the PowerShell executable running this script, for child runs.
    .OUTPUTS
        System.String. Path to pwsh (or powershell.exe under 5.1).
    #>
    return (Get-Process -Id $PID).Path
}

function Test-PsmuxAlive {
    <#
    .SYNOPSIS
        Reports whether any psmux server is still running.
    .DESCRIPTION
        Current psmux answers `ls` with exit 1 when no server runs; older builds
        answered exit 0 with no output. Either one means gone.
    .PARAMETER PsmuxBin
        Path to the psmux executable.
    .OUTPUTS
        System.Boolean.
    #>
    param([Parameter(Mandatory)][string]$PsmuxBin)

    $sessions = & $PsmuxBin ls 2>$null | Out-String
    return ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($sessions))
}

function Invoke-ResurrectSave {
    <#
    .SYNOPSIS
        Runs psmux-resurrect's save script once.
    .DESCRIPTION
        Runs it as a child process: the script sets process-wide state and
        calls `exit`, neither of which should reach this loop.
    #>
    $save = Join-Path $HOME '.psmux\plugins\psmux-resurrect\scripts\save.ps1'
    if (-not (Test-Path -LiteralPath $save)) { return }
    & (Get-PwshPath) -NoProfile -NonInteractive -File $save *> $null
}

function Invoke-SaveLoop {
    <#
    .SYNOPSIS
        Saves every IntervalMinutes until no psmux server is left.
    .PARAMETER Interval
        Minutes between saves.
    #>
    param([Parameter(Mandatory)][int]$Interval)

    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($true, $script:MUTEX_NAME, [ref]$createdNew)
    if (-not $createdNew) { $mutex.Dispose(); return }

    try {
        $psmuxBin = Get-PsmuxBin
        while ($true) {
            $due = (Get-Date).AddMinutes([math]::Max(1, $Interval))
            while ((Get-Date) -lt $due) {
                Start-Sleep -Seconds $script:LIVENESS_SECONDS
                if (-not (Test-PsmuxAlive -PsmuxBin $psmuxBin)) { return }
            }
            Invoke-ResurrectSave
        }
    }
    finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

if ($Worker) {
    Invoke-SaveLoop -Interval $IntervalMinutes
} else {
    Start-Process -FilePath (Get-PwshPath) -WindowStyle Hidden -ArgumentList @(
        '-NoProfile'
        '-NonInteractive'
        '-File', $PSCommandPath
        '-Worker'
        '-IntervalMinutes', $IntervalMinutes
    )
}
