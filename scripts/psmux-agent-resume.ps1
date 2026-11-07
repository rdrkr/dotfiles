#Requires -Version 5.1
<#
.SYNOPSIS
    Makes a psmux boot-time restore reopen the Claude Code conversation each pane
    was in - the psmux counterpart of the tmux-restore plugin.
.DESCRIPTION
    tmux-restore cannot run here: it is POSIX shell, and it works through a
    tmux-resurrect save hook, which psmux-resurrect does not have yet. So the same
    idea is split in two steps around psmux-resurrect's own save and restore:

      -Record  Run by psmux-autosave.ps1 after each save. Writes
               ~\.psmux\resurrect\agents.json, mapping session:window.pane to the
               command that resumes that pane's conversation.
      -Apply   Run by profile.ps1 just before the boot-time restore. Copies those
               commands into the panes of the last save, and restore.ps1 then
               sends them, because @resurrect-processes in ~/.psmux.conf has
               '~claude'.

    The map is a separate file rather than a rewrite of each save because
    save.ps1 compares a save against the previous one to skip duplicates. Saves
    with rewritten commands would never match the live panes, so every tick would
    write a new file and push real history out of its rotation of 20.

    Claude Code registers each running session in <config>\sessions\<pid>.json.
    A pane is found from that entry's `tmux` field ("session:@1.%2") or, if that
    is empty, by walking up the process's parents to a pane's shell. Entries for
    processes that are gone are ignored. Only Claude Code is handled; a pane
    running anything else restores exactly as it did before.
.PARAMETER Record
    Writes the pane-to-conversation map.
.PARAMETER Apply
    Copies the map into the last save.
.EXAMPLE
    pwsh -NoProfile -File psmux-agent-resume.ps1 -Record
.NOTES
    Everything written to the map is typed into a shell on restore, so ids and
    flag values are checked against strict patterns first.
#>

param(
    [switch]$Record,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

## Hops allowed when walking up parent processes. Windows reuses pids, so a stale
## ParentProcessId can form a loop.
$script:MAX_PARENT_HOPS = 32

## Flags carried over to the resumed process. An allow-list, as the rest of a
## command line can be an initial prompt, which must not be sent again.
$script:KEEP_FLAGS = '(?:^|\s)(--dangerously-skip-permissions|--(?:model|effort|permission-mode)[= ][\w.:\[\]-]+)(?=\s|$)'

function Get-ClaudeDir {
    <#
    .SYNOPSIS
        Returns Claude Code's configuration directory.
    .OUTPUTS
        System.String.
    #>
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    return (Join-Path $env:USERPROFILE '.claude')
}

function Get-MapPath {
    <#
    .SYNOPSIS
        Returns the path of the pane-to-conversation map.
    .OUTPUTS
        System.String.
    #>
    return (Join-Path $env:USERPROFILE '.psmux\resurrect\agents.json')
}

function Get-OptionalField {
    <#
    .SYNOPSIS
        Reads a property that may be absent, which strict mode would reject.
    .PARAMETER Object
        Object parsed from JSON.
    .PARAMETER Name
        Property name.
    .OUTPUTS
        The value, or $null when the property does not exist.
    #>
    param($Object, [Parameter(Mandatory)][string]$Name)

    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-ProcessTable {
    <#
    .SYNOPSIS
        Snapshots every process once, for parent walks and command lines.
    .OUTPUTS
        System.Collections.Hashtable. Pid to an object with ParentId and CommandLine.
    #>
    $table = @{}
    foreach ($process in (Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, CommandLine)) {
        $table[[int]$process.ProcessId] = [pscustomobject]@{
            ParentId    = [int]$process.ParentProcessId
            CommandLine = [string]$process.CommandLine
        }
    }
    return $table
}

function Get-PsmuxPane {
    <#
    .SYNOPSIS
        Lists every pane of every session.
    .DESCRIPTION
        Walks sessions and windows the way psmux-resurrect's save does, so the keys
        line up with the save. psmux runs one server per session, so a pane id is
        only unique together with its session.
    .OUTPUTS
        PSCustomObject. Key (session:window.pane), Session, PaneId and PanePid.
    #>
    foreach ($session in (& psmux list-sessions -F '#{session_name}' 2>$null)) {
        $session = "$session".Trim()
        if (-not $session) { continue }

        foreach ($window in (& psmux list-windows -t $session -F '#{window_index}' 2>$null)) {
            $window = "$window".Trim()
            if ($window -notmatch '^\d+$') { continue }

            foreach ($line in (& psmux list-panes -t "${session}:$window" -F '#{pane_index}|#{pane_id}|#{pane_pid}' 2>$null)) {
                $parts = "$line".Trim() -split '\|'
                if ($parts.Count -lt 3 -or $parts[0] -notmatch '^\d+$') { continue }

                [pscustomobject]@{
                    Key     = "${session}:$window.$($parts[0])"
                    Session = $session
                    PaneId  = $parts[1]
                    PanePid = $parts[2]
                }
            }
        }
    }
}

function Find-AgentPane {
    <#
    .SYNOPSIS
        Finds the pane a registered Claude Code session runs in.
    .PARAMETER Entry
        Parsed registry entry.
    .PARAMETER Panes
        Result of Get-PsmuxPane.
    .PARAMETER Processes
        Result of Get-ProcessTable.
    .OUTPUTS
        The matching pane, or $null.
    #>
    param($Entry, [object[]]$Panes, [hashtable]$Processes)

    $location = [string](Get-OptionalField $Entry 'tmux')
    if ($location -match '^(.*):@\d+\.(%\d+)$') {
        $session = $Matches[1]
        $paneId = $Matches[2]
        $pane = $Panes | Where-Object { $_.Session -eq $session -and $_.PaneId -eq $paneId } | Select-Object -First 1
        if ($pane) { return $pane }
    }

    $current = [int]$Entry.pid
    for ($hop = 0; $hop -lt $script:MAX_PARENT_HOPS; $hop++) {
        if (-not $Processes.ContainsKey($current)) { return $null }
        $current = $Processes[$current].ParentId

        $id = "$current"
        $pane = $Panes | Where-Object { $_.PanePid -eq $id } | Select-Object -First 1
        if ($pane) { return $pane }
    }
    return $null
}

function Get-ResumeCommand {
    <#
    .SYNOPSIS
        Builds the command that reopens a conversation with the flags it had.
    .DESCRIPTION
        A session with nothing typed yet has no transcript to resume, so it is
        started under the same id instead.
    .PARAMETER SessionId
        The conversation's id.
    .PARAMETER CommandLine
        The running process's command line.
    .PARAMETER ClaudeDir
        Claude Code's configuration directory.
    .OUTPUTS
        System.String, or $null when the id is not a well-formed uuid.
    #>
    param(
        [string]$SessionId,
        [string]$CommandLine,
        [Parameter(Mandatory)][string]$ClaudeDir
    )

    if ($SessionId -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { return $null }

    $transcript = Get-ChildItem -Path (Join-Path $ClaudeDir 'projects') -Filter "$SessionId.jsonl" -Recurse -Depth 1 |
        Select-Object -First 1
    $flag = if ($transcript) { '--resume' } else { '--session-id' }

    $kept = foreach ($match in [regex]::Matches($CommandLine, $script:KEEP_FLAGS)) { $match.Groups[1].Value }
    return (@('claude', $flag, $SessionId) + @($kept)) -join ' '
}

function Invoke-Record {
    <#
    .SYNOPSIS
        Writes the map of panes to resume commands.
    .DESCRIPTION
        Leaves the previous map alone when no pane can be listed, since that means
        the server is down and not that the agents are gone. The write goes through
        a temporary file, so a restore never reads half a map.
    #>
    $panes = @(Get-PsmuxPane)
    if ($panes.Count -eq 0) { return }

    $claudeDir = Get-ClaudeDir
    $processes = Get-ProcessTable
    $map = @{}

    foreach ($file in (Get-ChildItem -Path (Join-Path $claudeDir 'sessions') -Filter '*.json' -File)) {
        $entry = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        if (-not $entry -or (Get-OptionalField $entry 'kind') -ne 'interactive') { continue }

        $entryPid = Get-OptionalField $entry 'pid'
        if ($null -eq $entryPid -or -not $processes.ContainsKey([int]$entryPid)) { continue }

        # a recycled pid: the number is alive, but it is no longer Claude Code
        $commandLine = $processes[[int]$entryPid].CommandLine
        if ($commandLine -notmatch 'claude') { continue }

        $pane = Find-AgentPane -Entry $entry -Panes $panes -Processes $processes
        if (-not $pane) { continue }

        $command = Get-ResumeCommand -SessionId (Get-OptionalField $entry 'sessionId') -CommandLine $commandLine -ClaudeDir $claudeDir
        if ($command) { $map[$pane.Key] = $command }
    }

    $path = Get-MapPath
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    $map | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath "$path.tmp" -Encoding UTF8
    Move-Item -LiteralPath "$path.tmp" -Destination $path -Force
}

function Invoke-Apply {
    <#
    .SYNOPSIS
        Copies the recorded resume commands into the last save.
    #>
    $mapPath = Get-MapPath
    $last = Join-Path (Split-Path $mapPath) 'last'
    if (-not (Test-Path -LiteralPath $mapPath) -or -not (Test-Path -LiteralPath $last)) { return }

    $savePath = (Get-Content -LiteralPath $last -Raw).Trim()
    if (-not (Test-Path -LiteralPath $savePath)) { return }

    $map = Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json
    $save = Get-Content -LiteralPath $savePath -Raw | ConvertFrom-Json
    if (-not $map -or -not $save) { return }

    $changed = $false
    foreach ($session in @($save.sessions)) {
        foreach ($window in @($session.windows)) {
            foreach ($pane in @($window.panes)) {
                $command = Get-OptionalField $map "$($session.name):$($window.index).$($pane.index)"
                if ($command) {
                    $pane.command = $command
                    $changed = $true
                }
            }
        }
    }

    if ($changed) {
        $save | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $savePath -Encoding UTF8
    }
}

if ($Record) { Invoke-Record }
elseif ($Apply) { Invoke-Apply }
