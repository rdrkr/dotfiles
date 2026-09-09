#Requires -Version 5.1
<#
.SYNOPSIS
    Publishes CPU and RAM figures into a psmux server's options from a single
    long-lived process, replacing psmux-cpu's per-tick `run-shell` poll.
.DESCRIPTION
    psmux-cpu polls by hanging `run-shell "pwsh -File system_stats.ps1"` off the
    status-interval hook. That makes the psmux *server* start a process on every
    status-bar tick, in every server, and psmux runs run-shell synchronously - so
    each tick stalls the redraw for as long as PowerShell takes to start, and
    intermittently fails outright:

        run-shell: pwsh -NoProfile -File "...\system_stats.ps1":
        The handle is invalid. (os error 6)

    ERROR_INVALID_HANDLE is CreateProcess declining to inherit the standard
    handles of a server that has no console of its own, which is the normal state
    for a psmux server spawned into the background (the warm pool in particular).
    The spawn itself is what fails, so nothing inside system_stats.ps1 can harden
    against it; the fix is to stop asking the server to spawn on a timer.

    So this script runs one long-lived process per server and does the polling
    itself, where the handles are valid.

    It is deliberately NOT launched from ~/.psmux.conf: a `run-shell` in the
    config is still the server spawning a process, so on exactly the servers that
    need this it is the call that fails. It is launched from profile.ps1 instead,
    by the first pane shell of a server - an ordinary interactive process with a
    console of its own. A named mutex keyed on the server pid keeps later panes
    from stacking duplicates.

    It also collapses the six `psmux set` calls system_stats.ps1 makes per tick
    into one chained invocation, so a poll costs one process rather than seven.

    Targeting: the worker inherits $env:TMUX from the pane shell, so a bare
    `psmux set` resolves to that pane's own server. The pid embedded in $env:TMUX
    is also how the worker knows when to stop: once the server is gone there is
    no status bar left to feed.
.PARAMETER ServerPid
    Process id of the psmux server to feed. Only needed to override the pid read
    out of $env:TMUX; leave it unset in normal use. Drives both liveness and the
    single-instance mutex, and falls back to failure counting when neither is
    available.
.PARAMETER Worker
    Internal. Set on the re-launched copy that runs the poll loop; the first
    invocation only detaches that copy and exits.
.PARAMETER IntervalSeconds
    Seconds between polls. Defaults to 5, matching psmux-cpu's status-interval.
.EXAMPLE
    pwsh -NoProfile -File psmux-stats-daemon.ps1
    Detaches a worker for the current pane's server. Run from inside a psmux pane
    to restart polling by hand after killing the daemon.
.NOTES
    ~/.psmux.conf unsets the psmux-cpu hooks this replaces; profile.ps1 starts it.
    Keep the option names below in sync with the status-right in ~/.psmux.conf.
#>

param(
    [int]$ServerPid = 0,
    [switch]$Worker,
    [int]$IntervalSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

function Get-PsmuxBin {
    <#
    .SYNOPSIS
        Resolves the psmux executable to call.
    .DESCRIPTION
        Mirrors psmux-cpu's own lookup order so this script targets whatever
        binary the rest of the plugin would have used.
    .OUTPUTS
        System.String. Full path to the executable, or the bare name 'psmux' when
        none of the candidates is on PATH.
    #>
    foreach ($name in @('psmux', 'pmux', 'tmux')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return 'psmux'
}

function Get-PsmuxServerPid {
    <#
    .SYNOPSIS
        Extracts the psmux server's process id from $env:TMUX.
    .DESCRIPTION
        $env:TMUX has the form "/tmp/psmux-<pid>/<socket>,<client>,<n>". The pid
        is the liveness handle for the server this daemon feeds.
    .OUTPUTS
        System.Int32 pid, or 0 when $env:TMUX is absent or unparseable - in which
        case the caller falls back to consecutive publish failures to decide when
        to exit.
    #>
    if ($env:TMUX -match 'psmux-(\d+)') { return [int]$Matches[1] }
    return 0
}

function Start-DetachedWorker {
    <#
    .SYNOPSIS
        Re-launches this script as a hidden background worker and returns at once.
    .DESCRIPTION
        Lets the script be run by hand from a pane without tying up that shell.
        Start-Process inherits the current environment, which carries $env:TMUX
        through to the worker and keeps it pointed at the launching server.
        profile.ps1 skips this hop and starts the worker directly.
    .PARAMETER ScriptPath
        Full path to this script file.
    .PARAMETER Interval
        Poll interval in seconds to pass through to the worker.
    .PARAMETER TargetPid
        Server pid to pass through to the worker; 0 when unknown.
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][int]$Interval,
        [int]$TargetPid = 0
    )

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwshPath = if ($pwsh) { $pwsh.Source } else { 'pwsh' }

    Start-Process -FilePath $pwshPath -WindowStyle Hidden -ArgumentList @(
        '-NoProfile'
        '-NonInteractive'
        '-File', $ScriptPath
        '-Worker'
        '-IntervalSeconds', $Interval
        '-ServerPid', $TargetPid
    )
}

function Get-SystemStats {
    <#
    .SYNOPSIS
        Samples CPU load and physical memory use.
    .DESCRIPTION
        Uses the same CIM classes as psmux-cpu's system_stats.ps1 so the numbers
        on the status bar do not shift when this daemon takes the poll over.
    .OUTPUTS
        System.Collections.Hashtable with keys Cpu (percent), Ram (percent),
        RamUsed and RamTotal (gibibytes, one decimal).
    #>
    $cpu = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    if (-not $cpu) { $cpu = 0 }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os) {
        $total = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $free  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $used  = [math]::Round($total - $free, 1)
        $pct   = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 0) } else { 0 }
    } else {
        $total = 0; $used = 0; $pct = 0
    }

    return @{
        Cpu      = [math]::Round($cpu, 0)
        Ram      = $pct
        RamUsed  = $used
        RamTotal = $total
    }
}

function Get-LoadColour {
    <#
    .SYNOPSIS
        Maps a load percentage to a psmux style tag.
    .DESCRIPTION
        Thresholds match psmux-cpu: green below 30, yellow below 80, red above.
        Only the @*_display options carry these; the status bar in ~/.psmux.conf
        styles the modules itself and consumes the bare percentages.
    .PARAMETER Percent
        Load percentage to classify.
    .OUTPUTS
        System.String. A psmux "#[fg=...]" style tag.
    #>
    param([Parameter(Mandatory)][int]$Percent)

    if ($Percent -lt 30) { return '#[fg=green]' }
    if ($Percent -lt 80) { return '#[fg=yellow]' }
    return '#[fg=red]'
}

function Publish-Stats {
    <#
    .SYNOPSIS
        Writes one sample into the launching server's options.
    .DESCRIPTION
        All six options go out in a single chained psmux command - psmux accepts
        ';' as an argument separator between commands - so a poll costs one
        process instead of one per option.
    .PARAMETER PsmuxBin
        Path to the psmux executable.
    .PARAMETER Stats
        A sample from Get-SystemStats.
    .OUTPUTS
        System.Boolean. True when psmux accepted the command.
    #>
    param(
        [Parameter(Mandatory)][string]$PsmuxBin,
        [Parameter(Mandatory)][hashtable]$Stats
    )

    $cpuDisplay = "$(Get-LoadColour $Stats.Cpu)CPU:$($Stats.Cpu)%#[default]"
    $ramDisplay = "$(Get-LoadColour $Stats.Ram)MEM:$($Stats.Ram)%#[default]"

    & $PsmuxBin `
        set -g '@cpu_percentage' "$($Stats.Cpu)%" ';' `
        set -g '@cpu_display'    $cpuDisplay ';' `
        set -g '@ram_percentage' "$($Stats.Ram)%" ';' `
        set -g '@ram_display'    $ramDisplay ';' `
        set -g '@ram_used'       "$($Stats.RamUsed)G" ';' `
        set -g '@ram_total'      "$($Stats.RamTotal)G" 2>&1 | Out-Null

    return ($LASTEXITCODE -eq 0)
}

function Invoke-PollLoop {
    <#
    .SYNOPSIS
        Polls and publishes until the launching psmux server goes away.
    .DESCRIPTION
        A named mutex keyed on the server pid keeps one daemon per server, so a
        re-sourced config cannot stack duplicates. The loop ends when that server
        exits; if the pid was unavailable it ends after three consecutive publish
        failures instead, which is the same signal by a slower route.
    .PARAMETER Interval
        Seconds to wait between samples.
    .PARAMETER TargetPid
        Server pid to watch; 0 falls back to the pid in $env:TMUX.
    #>
    param(
        [Parameter(Mandatory)][int]$Interval,
        [int]$TargetPid = 0
    )

    $psmuxBin  = Get-PsmuxBin
    $serverPid = if ($TargetPid -gt 0) { $TargetPid } else { Get-PsmuxServerPid }
    $mutexName = "Local\psmux-stats-daemon-$serverPid"

    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
    if (-not $createdNew) { return }

    try {
        $failures = 0
        while ($true) {
            if ($serverPid -gt 0 -and -not (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)) {
                break
            }

            if (Publish-Stats -PsmuxBin $psmuxBin -Stats (Get-SystemStats)) {
                $failures = 0
            } else {
                $failures++
                if ($serverPid -le 0 -and $failures -ge 3) { break }
            }

            Start-Sleep -Seconds $Interval
        }
    }
    finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

if ($Worker) {
    Invoke-PollLoop -Interval $IntervalSeconds -TargetPid $ServerPid
} else {
    Start-DetachedWorker -ScriptPath $PSCommandPath -Interval $IntervalSeconds -TargetPid $ServerPid
}
