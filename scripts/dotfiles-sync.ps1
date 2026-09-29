#Requires -Version 7.0
<#
.SYNOPSIS
    dotfiles-sync for Windows: keep two dotfiles repos in sync by content, never by history.

.DESCRIPTION
    Native PowerShell implementation of scripts/dotfiles-sync.sh, speaking the
    same patch format and sharing the same per-clone state, so a Windows clone
    and a macOS/Linux clone can exchange changes over Taildrop.

    Changes travel between the two repos as patch files and each one lands in
    the receiving repo as a new commit made with that repo's own git identity,
    carrying a "Dotfiles-Sync-Source: <label> <sha>" trailer. No commit, author
    or history ever crosses over.

    Usage:
      dotfiles-sync setup --label NAME --peer DEVICE [--email REGEX]
      dotfiles-sync export [--no-send] [--yes]    send new commits to the peer
      dotfiles-sync import [--auto] [FILE...]     review and apply what arrived
      dotfiles-sync snapshot [--no-send] [--yes]  send every file (first sync)
      dotfiles-sync baseline [COMMIT]             mark COMMIT (default HEAD) as synced
      dotfiles-sync flush                         send patches still queued in the outbox
      dotfiles-sync auto                          one unattended sync cycle
      dotfiles-sync watch [--debounce S] [--poll S] [--max-wait S]
                                                  run 'auto' whenever the repo changes
      dotfiles-sync schedule | unschedule         run 'watch' at logon (+ 15-min fallback)
      dotfiles-sync status

    Continuous sync: 'schedule' registers two Task Scheduler tasks for the
    current user. DotfilesSyncWatch starts 'watch' at logon: a FileSystemWatcher
    on the repo that runs 'auto' once the tree has been quiet for --debounce
    seconds (default 120), and every --poll seconds (default 300) to pick up
    what Taildrop delivered and retry queued sends. DotfilesSyncTick runs 'auto'
    every 15 minutes in case the watcher is not running.

    'auto' commits local changes, applies what the peer sent and sends what is
    new. Outgoing changes are scanned for secrets and never sent when the scan
    fails. An incoming change that does not apply cleanly is moved to
    .git\dotfiles-sync\inbox\held\, a notification is shown, and nothing more is
    applied until an interactive 'dotfiles-sync import' has dealt with it.
    Snapshots are never applied unattended.

    Per-clone settings live in the repo's local git config (never committed):
      dotfiles-sync.label   this side's name, e.g. "personal" or "work"
      dotfiles-sync.peer    Tailscale device name of the other machine
      dotfiles-sync.email   regex every pushed author/committer email must match

    Files that must never cross are listed in .syncignore; patterns that must
    never leave this machine go in .git\dotfiles-sync\blocklist.

    The repo defaults to ~\dotfiles; set $env:DOTFILES_SYNC_REPO or pass -C DIR.
    $env:DOTFILES_SYNC_TAILSCALE overrides the tailscale CLI,
    $env:DOTFILES_SYNC_DOWNLOADS (";"-separated) the folders searched for
    Taildrop files, and $env:DOTFILES_SYNC_NO_NOTIFY=1 turns notifications off
    (the tests use these).

.EXAMPLE
    pwsh -File scripts\dotfiles-sync.ps1 status

.EXAMPLE
    pwsh -File scripts\dotfiles-sync.ps1 -C C:\Users\me\dotfiles import --auto
#>

# Arguments are parsed by hand ($args) rather than with a param() block, so the
# same "--no-send" / "-C DIR" syntax as the bash script works unchanged.

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

# --- constants --------------------------------------------------------------

<# First line of every patch file. #>
$script:PatchHeader = '# dotfiles-sync patch v1'
<# Commit trailer that names the peer commit an imported change came from. #>
$script:Trailer = 'Dotfiles-Sync-Source'
<# Message of the commit 'auto' makes for local changes. #>
$script:AutoCommitMsg = 'chore(sync): auto-commit local changes'
<# Task Scheduler task running 'watch' at logon. #>
$script:WatchTaskName = 'DotfilesSyncWatch'
<# Task Scheduler task running 'auto' every 15 minutes. #>
$script:TickTaskName = 'DotfilesSyncTick'
<# Byte-transparent encoding for reading and writing patch contents. #>
$script:Latin1 = [Text.Encoding]::Latin1
<# UTF-8 without BOM, for header lines and state files. #>
$script:Utf8 = [Text.UTF8Encoding]::new($false)
<# Secret patterns every outgoing file is checked against (same as the bash script). #>
$script:BuiltinSecretPatterns = @(
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'gh[pousr]_[A-Za-z0-9]{36,}'
    'github_pat_[A-Za-z0-9_]{22,}'
    'AKIA[0-9A-Z]{16}'
    'xox[abprs]-[A-Za-z0-9-]{10,}'
    'glpat-[A-Za-z0-9_-]{20,}'
    'sk-(ant-)?[A-Za-z0-9_-]{20,}'
    # any browser cookie-jar line (Netscape format), whatever the cookie holds
    '(TRUE|FALSE)\t/[^\t]*\t(TRUE|FALSE)\t[0-9]+\t[^\t]+\t[^\t]+'
)

# --- per-run state ----------------------------------------------------------

<# Absolute path of the repo's top level, with forward slashes. #>
$script:Repo = if ($env:DOTFILES_SYNC_REPO) { $env:DOTFILES_SYNC_REPO } else { Join-Path $HOME 'dotfiles' }
<# Path of sync.log once the repo is known. #>
$script:SyncLog = $null
<# Open handle on the lock file while this process holds the sync lock. #>
$script:LockStream = $null
<# True while an 'auto' cycle runs, so its outcome is written to last-run. #>
$script:AutoRun = $false
<# Outcome of the current 'auto' cycle: ok, held, blocked, queued, skipped or error. #>
$script:LastRunStatus = ''
<# Details for last-run. #>
$script:LastRunMsg = ''
<# Process exit code set by the command. #>
$script:ExitCode = 0

# --- output and errors ------------------------------------------------------

<#
.SYNOPSIS
    Stops the current command with an error message.
.PARAMETER Message
    What went wrong.
#>
function Stop-Sync {
    param([Parameter(Mandatory)][string]$Message)
    $ex = [InvalidOperationException]::new($Message)
    $ex.Data['dotfiles-sync'] = $true
    throw $ex
}

<#
.SYNOPSIS
    Appends a timestamped line to .git\dotfiles-sync\sync.log, keeping it under about 1 MB.
.PARAMETER Message
    Line to record.
#>
function Write-SyncLog {
    param([string]$Message)
    if (-not $script:SyncLog) { return }
    try {
        $line = '{0} [{1}] {2}' -f (Get-Date -Format "yyyy-MM-dd'T'HH:mm:sszzz"), $PID, $Message
        [IO.File]::AppendAllText($script:SyncLog, "$line`n", $script:Utf8)
        if ((Get-Item -LiteralPath $script:SyncLog).Length -gt 1MB) {
            $keep = Get-Content -LiteralPath $script:SyncLog -Tail 2000
            [IO.File]::WriteAllText($script:SyncLog, (($keep -join "`n") + "`n"), $script:Utf8)
        }
    }
    catch { }
}

<#
.SYNOPSIS
    Prints a progress line (to stderr, like the bash script) and logs it.
.PARAMETER Message
    Line to show.
#>
function Write-Info {
    param([string]$Message)
    [Console]::Error.WriteLine("==> $Message")
    Write-SyncLog $Message
}

<#
.SYNOPSIS
    Shows a Windows toast notification (BurntToast when installed, else the
    WinRT toast API through Windows PowerShell) and logs it. Never fails.
.PARAMETER Title
    Notification title.
.PARAMETER Message
    Notification text.
#>
function Send-SyncNotification {
    param([string]$Title, [string]$Message)
    Write-SyncLog "notify: $Title - $Message"
    if ($env:DOTFILES_SYNC_NO_NOTIFY -eq '1') { return }
    try {
        $t = [Security.SecurityElement]::Escape($Title)
        $m = [Security.SecurityElement]::Escape($Message)
        $ps = @"
if (Get-Module -ListAvailable -Name BurntToast) {
    New-BurntToastNotification -Text '$($Title -replace "'", "''")', '$($Message -replace "'", "''")'
} else {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    `$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    `$doc.LoadXml('<toast><visual><binding template="ToastText02"><text id="1">$t</text><text id="2">$m</text></binding></visual></toast>')
    `$app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(`$app).Show([Windows.UI.Notifications.ToastNotification]::new(`$doc))
}
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps))
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden `
            -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded | Out-Null
    }
    catch { Write-SyncLog "notification failed: $($_.Exception.Message)" }
}

# --- git and config ---------------------------------------------------------

<#
.SYNOPSIS
    Runs git against the dotfiles repo and returns its output lines.
.PARAMETER GitArgs
    Arguments for git.
.PARAMETER AllowFail
    Return the output even when git exits non-zero (check $LASTEXITCODE).
.PARAMETER Quiet
    Discard git's stderr.
#>
function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$GitArgs, [switch]$AllowFail, [switch]$Quiet)
    if ($Quiet) { $out = & git -C $script:Repo @GitArgs 2>$null }
    else { $out = & git -C $script:Repo @GitArgs }
    if ($LASTEXITCODE -ne 0 -and -not $AllowFail) {
        Stop-Sync "git $($GitArgs -join ' ') failed (exit $LASTEXITCODE)"
    }
    return $out
}

<#
.SYNOPSIS
    Succeeds (returns $true) when a git command exits 0; its output is discarded.
.PARAMETER GitArgs
    Arguments for git.
#>
function Test-Git {
    param([Parameter(Mandatory)][string[]]$GitArgs)
    & git -C $script:Repo @GitArgs *> $null
    return ($LASTEXITCODE -eq 0)
}

<#
.SYNOPSIS
    Returns a dotfiles-sync.* setting from the repo's local git config, or ''.
.PARAMETER Name
    Setting name without the "dotfiles-sync." prefix.
#>
function Get-SyncConfig {
    param([Parameter(Mandatory)][string]$Name)
    $v = Invoke-Git -GitArgs @('config', '--get', "dotfiles-sync.$Name") -AllowFail
    if ($LASTEXITCODE -ne 0 -or $null -eq $v) { return '' }
    return ([string]($v | Select-Object -First 1)).Trim()
}

<#
.SYNOPSIS
    Returns the trailer value (the "<label> <sha>" source) of a commit, or ''.
.PARAMETER Commit
    Commit to inspect.
#>
function Get-SyncTrailer {
    param([Parameter(Mandatory)][string]$Commit)
    $fmt = "--format=%(trailers:key=$($script:Trailer),valueonly)"
    $v = Invoke-Git -GitArgs @('log', '-1', $fmt, $Commit)
    return (($v | Where-Object { $_ }) -join "`n").Trim()
}

<#
.SYNOPSIS
    Returns (and creates) the per-clone state directory inside .git.
#>
function Get-StateDir {
    $gitDir = [string](Invoke-Git -GitArgs @('rev-parse', '--absolute-git-dir'))
    $dir = Join-Path $gitDir 'dotfiles-sync'
    foreach ($sub in 'outbox\sent', 'outbox\manual', 'inbox\done', 'inbox\held') {
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $dir $sub)
    }
    return $dir
}

<#
.SYNOPSIS
    Writes a small state file with LF line endings and no BOM, so the bash
    script can read the same file.
.PARAMETER Path
    File to write.
.PARAMETER Line
    Content (a newline is added).
.PARAMETER Append
    Append instead of replacing.
#>
function Write-StateFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Line, [switch]$Append)
    if ($Append) { [IO.File]::AppendAllText($Path, "$Line`n", $script:Utf8) }
    else { [IO.File]::WriteAllText($Path, "$Line`n", $script:Utf8) }
}

<#
.SYNOPSIS
    Reads a small state file and returns its trimmed content, or '' when missing.
.PARAMETER Path
    File to read.
#>
function Read-StateFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return ([IO.File]::ReadAllText($Path)).Trim()
}

# --- locking ----------------------------------------------------------------

<#
.SYNOPSIS
    Returns $true while the bash implementation holds its lock (the lock.d
    directory) in this clone - e.g. install.sh backup running in WSL on the
    same repo. A lock.d older than 30 minutes is treated as left behind and
    removed; no bash run holds the lock that long.
.PARAMETER StateDir
    The .git\dotfiles-sync directory.
#>
function Test-BashSyncLock {
    param([Parameter(Mandatory)][string]$StateDir)
    $dir = Join-Path $StateDir 'lock.d'
    if (-not (Test-Path -LiteralPath $dir)) { return $false }
    if (((Get-Date) - (Get-Item -LiteralPath $dir).LastWriteTime).TotalMinutes -lt 30) { return $true }
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    return $false
}

<#
.SYNOPSIS
    Takes the per-clone sync lock: an exclusive handle on .git\dotfiles-sync\lock,
    which Windows releases by itself if the process dies (and which WSL and Git
    Bash see as unopenable, so the bash implementation waits for it too). Also
    waits while the bash implementation holds lock.d. Re-entrant within a run.
.PARAMETER WaitSeconds
    How long to wait for another run to finish.
.OUTPUTS
    $true when held, $false when another run still has it.
#>
function Enter-SyncLock {
    param([int]$WaitSeconds = 0)
    if ($script:LockStream) { return $true }
    $state = Get-StateDir
    $path = Join-Path $state 'lock'
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ($true) {
        try {
            $stream = [IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None')
            # checked after taking the handle, so a bash run that got in first is seen
            if (Test-BashSyncLock $state) { $stream.Dispose() }
            else {
                $script:LockStream = $stream
                $bytes = $script:Utf8.GetBytes("$PID`n")
                $script:LockStream.SetLength(0)
                $script:LockStream.Write($bytes, 0, $bytes.Length)
                $script:LockStream.Flush()
                return $true
            }
        }
        catch [IO.IOException] { }
        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Seconds 1
    }
}

<#
.SYNOPSIS
    Releases the sync lock if this process holds it.
#>
function Exit-SyncLock {
    if ($script:LockStream) {
        $script:LockStream.Dispose()
        $script:LockStream = $null
    }
}

<#
.SYNOPSIS
    Takes the lock for an interactive command, or stops when a sync is running.
#>
function Assert-SyncLock {
    if (-not (Enter-SyncLock 0)) {
        Stop-Sync "another dotfiles-sync run holds the lock ($(Join-Path (Get-StateDir) 'lock')); try again shortly"
    }
}

# --- patterns ---------------------------------------------------------------

<#
.SYNOPSIS
    Returns the non-empty, non-comment lines of a pattern file, without CR line
    endings, a UTF-8 BOM or surrounding whitespace.
.PARAMETER Path
    Pattern file (missing is fine).
#>
function Get-PatternLines {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $result = [Collections.Generic.List[string]]::new()
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $l = $line.TrimStart([char]0xFEFF)
        $hash = $l.IndexOf('#')
        if ($hash -ge 0) { $l = $l.Substring(0, $hash) }
        $l = $l.Trim()
        if ($l) { $result.Add($l) }
    }
    return $result.ToArray()
}

<#
.SYNOPSIS
    Returns the .syncignore patterns, plus .syncignore itself. A leading "/" is
    dropped (patterns are matched from the repo root anyway, and git refuses
    "/x" as a path outside the repo); "!" negations are not supported and are
    left out.
#>
function Get-SyncIgnorePatterns {
    '.syncignore'
    foreach ($p in Get-PatternLines (Join-Path $script:Repo '.syncignore')) {
        if ($p.StartsWith('!')) { continue }
        $p = $p.TrimStart('/')
        if ($p) { $p }
    }
}

<#
.SYNOPSIS
    Returns git diff pathspecs excluding every .syncignore pattern. A trailing
    "/" means the whole directory.
#>
function Get-ExcludePathspecs {
    $specs = foreach ($p in Get-SyncIgnorePatterns) {
        if ($p.EndsWith('/')) { ":(exclude,glob)$p**" } else { ":(exclude,glob)$p" }
    }
    return @($specs)
}

<#
.SYNOPSIS
    Returns git apply --exclude options for every .syncignore pattern.
#>
function Get-ExcludeApplyOptions {
    $opts = foreach ($p in Get-SyncIgnorePatterns) {
        if ($p.EndsWith('/')) { "--exclude=$p*" } else { "--exclude=$p" }
    }
    return @($opts)
}

# --- tailscale and incoming folders ------------------------------------------

<#
.SYNOPSIS
    Returns the path of tailscale.exe, or $null when it is not installed.
#>
function Get-TailscalePath {
    if ($env:DOTFILES_SYNC_TAILSCALE) { return $env:DOTFILES_SYNC_TAILSCALE }
    $cmd =Get-Command tailscale -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $candidate = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $null
}

<#
.SYNOPSIS
    Returns the folders Taildrop may have saved incoming files to: the user's
    Downloads folder (also when it was moved, e.g. into OneDrive).
#>
function Get-DownloadDirs {
    if ($null -ne $env:DOTFILES_SYNC_DOWNLOADS) {
        return @($env:DOTFILES_SYNC_DOWNLOADS -split [IO.Path]::PathSeparator | Where-Object { $_ })
    }
    $dirs = [Collections.Generic.List[string]]::new()
    $dirs.Add((Join-Path $HOME 'Downloads'))
    try {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $raw = (Get-ItemProperty -Path $key -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($raw) {
            $expanded = [Environment]::ExpandEnvironmentVariables($raw)
            if ($expanded -and -not $dirs.Contains($expanded)) { $dirs.Add($expanded) }
        }
    }
    catch { }
    return $dirs.ToArray()
}

<#
.SYNOPSIS
    Returns the Windows tar.exe (bsdtar). Git's GNU tar, which may come first on
    PATH, reads "C:\..." as a remote host and cannot be used.
#>
function Get-TarPath {
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $tar)) { Stop-Sync "tar.exe not found at $tar" }
    return $tar
}

# --- secret scan -------------------------------------------------------------

<#
.SYNOPSIS
    Checks what is about to leave this machine for secrets and local blocklist
    patterns, and runs gitleaks too when it is installed. Hits are printed with
    the secrets masked.
.PARAMETER Target
    A patch file, or a directory of snapshot files.
.OUTPUTS
    $true when clean, $false when something matched.
#>
function Test-OutgoingClean {
    param([Parameter(Mandatory)][string]$Target)
    $blocklist = @(Get-PatternLines (Join-Path (Get-StateDir) 'blocklist'))
    $all = @($script:BuiltinSecretPatterns) + $blocklist
    $scan = [regex]::new((($all | ForEach-Object { "(?:$_)" }) -join '|'), 'Compiled')
    $redact = [regex]::new((($script:BuiltinSecretPatterns | ForEach-Object { "(?:$_)" }) -join '|'), 'Compiled')

    $isDir = Test-Path -LiteralPath $Target -PathType Container
    $files = if ($isDir) { Get-ChildItem -LiteralPath $Target -Recurse -File -Force } else { Get-Item -LiteralPath $Target }
    $hits = [Collections.Generic.List[string]]::new()
    foreach ($file in $files) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        # like grep -I: skip binary files
        $probe = [Math]::Min($bytes.Length, 8000)
        if ($probe -gt 0 -and [Array]::IndexOf($bytes, [byte]0, 0, $probe) -ge 0) { continue }
        $name = if ($isDir) { '.' + $file.FullName.Substring((Resolve-Path -LiteralPath $Target).Path.TrimEnd('\').Length).Replace('\', '/') } else { $file.FullName }
        $lines = $script:Latin1.GetString($bytes).Split("`n")
        for ($i = 0; $i -lt $lines.Length; $i++) {
            if ($scan.IsMatch($lines[$i])) {
                $shown = if ($isDir) { "${name}:$($i + 1):" } else { "$($i + 1):" }
                $shown += $redact.Replace($lines[$i].TrimEnd("`r"), '[redacted]')
                if ($shown.Length -gt 160) { $shown = $shown.Substring(0, 160) }
                $hits.Add($shown)
            }
        }
    }
    if ($hits.Count -gt 0) {
        $hits | ForEach-Object { [Console]::Error.WriteLine($_) }
        Write-Info 'outgoing changes match a secret or blocklist pattern (above) - nothing was sent. Untrack or fix those files, or list them in .syncignore, then retry.'
        return $false
    }

    if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
        $out = & gitleaks dir --no-banner --redact $Target 2>&1
        if ($LASTEXITCODE -ne 0) {
            $out | ForEach-Object { [Console]::Error.WriteLine([string]$_) }
            Write-Info 'gitleaks flagged the outgoing changes - nothing was sent.'
            return $false
        }
    }
    return $true
}

# --- sending -----------------------------------------------------------------

<#
.SYNOPSIS
    Returns the queued outbox files, oldest first.
#>
function Get-QueuedFiles {
    $outbox = Join-Path (Get-StateDir) 'outbox'
    return @(Get-ChildItem -LiteralPath $outbox -File -Filter 'dotfiles-sync-*' | Sort-Object Name)
}

<#
.SYNOPSIS
    Sends every queued outbox file to the peer with Taildrop, oldest first,
    moving each to outbox\sent\ once it has gone. Stops at the first failure so
    the peer always receives patches in order.
.OUTPUTS
    $true when the outbox is empty afterwards, $false when something is still queued.
#>
function Send-Outbox {
    $queued = @(Get-QueuedFiles)
    if ($queued.Count -eq 0) { return $true }
    $peer = Get-SyncConfig peer
    if (-not $peer) {
        Write-Info "no peer set (dotfiles-sync setup --peer DEVICE); $($queued.Count) file(s) stay queued"
        return $false
    }
    $ts = Get-TailscalePath
    if (-not $ts) {
        Write-Info "tailscale.exe not found; $($queued.Count) file(s) stay queued"
        return $false
    }
    $sent = Join-Path (Get-StateDir) 'outbox\sent'
    foreach ($f in $queued) {
        Write-Info "sending $($f.Name) to $peer over Taildrop"
        & $ts file cp $f.FullName "${peer}:" | ForEach-Object { [Console]::Error.WriteLine([string]$_) }
        if ($LASTEXITCODE -ne 0) {
            Write-Info "Taildrop failed; $($f.Name) stays queued and is retried on the next run"
            return $false
        }
        Move-Item -LiteralPath $f.FullName -Destination $sent -Force
    }
    return $true
}

<#
.SYNOPSIS
    Puts a finished patch or snapshot in the outbox and sends the queue, or
    leaves it in outbox\manual\ for a manual transfer.
.PARAMETER File
    The patch or snapshot.
.PARAMETER Keep
    Do not send; keep for a manual transfer.
.OUTPUTS
    $true when queued and sent (or kept), $false when the send failed.
#>
function Submit-SyncFile {
    param([Parameter(Mandatory)][string]$File, [switch]$Keep)
    $state = Get-StateDir
    $name = Split-Path -Leaf $File
    if ($Keep) {
        $dest = Join-Path $state 'outbox\manual'
        Move-Item -LiteralPath $File -Destination $dest -Force
        Write-Info "wrote $(Join-Path $dest $name) - move it to the other machine and run 'dotfiles-sync import FILE' there"
        return $true
    }
    Move-Item -LiteralPath $File -Destination (Join-Path $state 'outbox') -Force
    return (Send-Outbox)
}

<#
.SYNOPSIS
    Returns the commit exports start after: last-export, or - when a rebase has
    rewritten that commit out of this branch - its merge base with HEAD.
#>
function Get-ExportBase {
    $base = Read-StateFile (Join-Path (Get-StateDir) 'last-export')
    if (-not $base) { Stop-Sync 'no baseline yet: dotfiles-sync baseline' }
    if (-not (Test-Git @('merge-base', '--is-ancestor', $base, 'HEAD'))) {
        $fallback = Invoke-Git -GitArgs @('merge-base', $base, 'HEAD') -AllowFail -Quiet
        if ($LASTEXITCODE -ne 0 -or -not $fallback) {
            Stop-Sync "baseline $base is unknown here; run 'dotfiles-sync baseline' once both repos match"
        }
        $fallback = ([string]$fallback).Trim()
        Write-Info "baseline $($base.Substring(0, 10)) is no longer on this branch (rewritten by a rebase?); continuing from $($fallback.Substring(0, 10))"
        $base = $fallback
    }
    return $base
}

# --- commands ----------------------------------------------------------------

<#
.SYNOPSIS
    Stores this repo's sync settings and installs the pre-push identity check.
.PARAMETER Arguments
    --label NAME --peer DEVICE [--email REGEX]
#>
function Invoke-Setup {
    param([string[]]$Arguments)
    for ($i = 0; $i -lt $Arguments.Count; $i += 2) {
        $key = switch ($Arguments[$i]) {
            '--label' { 'label' } '--peer' { 'peer' } '--email' { 'email' }
            default { Stop-Sync "setup: unknown option $($Arguments[$i])" }
        }
        if ($i + 1 -ge $Arguments.Count) { Stop-Sync "setup: $($Arguments[$i]) needs a value" }
        $null = Invoke-Git -GitArgs @('config', "dotfiles-sync.$key", $Arguments[$i + 1])
    }
    if (-not (Get-SyncConfig label)) { Stop-Sync 'setup needs --label (e.g. personal or work)' }

    $gitDir = [string](Invoke-Git -GitArgs @('rev-parse', '--absolute-git-dir'))
    $hook = Join-Path $gitDir 'hooks\pre-push'
    $self = $PSCommandPath -replace '\\', '/'
    if ((Test-Path -LiteralPath $hook) -and -not (Select-String -LiteralPath $hook -Pattern 'dotfiles-sync' -Quiet)) {
        Write-Info "a pre-push hook already exists at $hook; add this line to it yourself:"
        Write-Info "  pwsh -NoProfile -File `"$self`" -C `"$($script:Repo)`" check-push `"`$@`" || exit 1"
    }
    else {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $hook)
        $body = "#!/bin/sh`n# installed by dotfiles-sync setup: refuses to push commits made under another identity`n" +
            "exec pwsh -NoProfile -NonInteractive -File `"$self`" -C `"$($script:Repo)`" check-push `"`$@`"`n"
        [IO.File]::WriteAllText($hook, $body, $script:Utf8)
    }

    $lastExport = Join-Path (Get-StateDir) 'last-export'
    if (-not (Read-StateFile $lastExport)) {
        Write-StateFile $lastExport ([string](Invoke-Git -GitArgs @('rev-parse', 'HEAD')))
        Write-Info "baseline set to HEAD - run this once both repos match (see 'snapshot')"
    }
    Show-Status
}

<#
.SYNOPSIS
    pre-push hook body: refuses the push when a new commit's author or
    committer email does not match dotfiles-sync.email. Reads git's
    "<local ref> <local sha> <remote ref> <remote sha>" lines from stdin.
.PARAMETER Arguments
    Remote name and URL (from git).
.OUTPUTS
    Process exit code: 0 to allow, 1 to refuse.
#>
function Invoke-CheckPush {
    param([string[]]$Arguments)
    $remote = if ($Arguments.Count -gt 0) { $Arguments[0] } else { '' }
    $pattern = Get-SyncConfig email
    if (-not $pattern) { return 0 }
    $zero = '0' * 40
    $bad = [Collections.Generic.List[string]]::new()
    $stdin = [Console]::In.ReadToEnd()
    foreach ($line in $stdin -split "`r?`n") {
        $f = $line.Trim() -split '\s+'
        if ($f.Count -lt 4) { continue }
        $localSha = $f[1]; $remoteSha = $f[3]
        if ($localSha -eq $zero) { continue }
        $range = if ($remoteSha -eq $zero) {
            Invoke-Git -GitArgs @('rev-list', $localSha, '--not', "--remotes=$remote")
        }
        else {
            Invoke-Git -GitArgs @('rev-list', "$remoteSha..$localSha")
        }
        foreach ($c in @($range | Where-Object { $_ })) {
            $emails = Invoke-Git -GitArgs @('log', '-1', '--format=%ae%n%ce', $c)
            if (@($emails | Where-Object { $_ -notmatch $pattern }).Count -gt 0) {
                $bad.Add([string](Invoke-Git -GitArgs @('log', '-1', '--format=  %h %ae / %ce  %s', $c)))
            }
        }
    }
    if ($bad.Count -gt 0) {
        [Console]::Error.WriteLine("dotfiles-sync: push refused - these commits use an identity not matching ${pattern}:")
        $bad | ForEach-Object { [Console]::Error.WriteLine($_) }
        return 1
    }
    return 0
}

<#
.SYNOPSIS
    Marks a commit as the last one the peer has, so the next export starts after it.
.PARAMETER Commit
    Commit (default HEAD).
#>
function Invoke-Baseline {
    param([string]$Commit = 'HEAD')
    $sha = Invoke-Git -GitArgs @('rev-parse', '--verify', "$Commit^{commit}") -AllowFail -Quiet
    if ($LASTEXITCODE -ne 0) { Stop-Sync "no such commit: $Commit" }
    Write-StateFile (Join-Path (Get-StateDir) 'last-export') ([string]$sha).Trim()
    Write-Info "baseline: $(Invoke-Git -GitArgs @('log', '-1', '--format=%h %s', $sha))"
}

<#
.SYNOPSIS
    Asks a question on the console (or reads the answer from redirected stdin)
    and returns it. Stops the command when there is nothing to read, so callers
    never loop on an empty answer.
.PARAMETER Prompt
    Question to show.
#>
function Read-Answer {
    param([Parameter(Mandatory)][string]$Prompt)
    $answer = $null
    try {
        if ([Console]::IsInputRedirected) {
            [Console]::Error.Write("$Prompt ")
            $answer = [Console]::In.ReadLine()
        }
        else { $answer = Read-Host -Prompt $Prompt }
    }
    catch { $answer = $null }
    if ($null -eq $answer) { Stop-Sync 'no answer (input closed) - run this in a terminal' }
    return $answer
}

<#
.SYNOPSIS
    Shows a file in a pager: $env:PAGER, else less, else Out-Host -Paging.
.PARAMETER Path
    File to show.
#>
function Show-InPager {
    param([Parameter(Mandatory)][string]$Path)
    # Start-Process hands the pager the real console; '&' inside a function
    # whose output is captured would pipe it into a variable instead
    $parts = @(if ($env:PAGER) { $env:PAGER -split '\s+' | Where-Object { $_ } }
        elseif (Get-Command less -ErrorAction SilentlyContinue) { 'less', '-R' })
    if ($parts.Count -gt 0) {
        $pagerArgs = @($parts | Select-Object -Skip 1) + "`"$Path`""
        Start-Process -FilePath $parts[0] -ArgumentList $pagerArgs -NoNewWindow -Wait
    }
    else { Get-Content -LiteralPath $Path | Out-Host -Paging }
}

<#
.SYNOPSIS
    Appends text to an open stream as UTF-8 bytes.
.PARAMETER Stream
    Destination stream.
.PARAMETER Text
    Text to write (newlines as given).
#>
function Write-StreamText {
    param([Parameter(Mandatory)][IO.Stream]$Stream, [Parameter(Mandatory)][string]$Text)
    $bytes = $script:Utf8.GetBytes($Text)
    $Stream.Write($bytes, 0, $bytes.Length)
}

<#
.SYNOPSIS
    Builds a patch of every commit since the last export (skipping ones that
    came from the peer), has it reviewed (unless --yes) and scanned, queues it
    in the outbox and sends the queue.
.PARAMETER Arguments
    [--no-send] [--yes]
.OUTPUTS
    $true when queued or nothing to send, $false when the scan blocked it or the send failed.
#>
function Invoke-Export {
    param([string[]]$Arguments)
    $keep = $false; $yes = $false
    foreach ($a in $Arguments) {
        switch ($a) {
            '--no-send' { $keep = $true }
            '--yes' { $yes = $true }
            default { Stop-Sync "export: unknown option $a" }
        }
    }
    $label = Get-SyncConfig label
    if (-not $label) { Stop-Sync 'not set up: dotfiles-sync setup --label NAME --peer DEVICE' }
    Assert-SyncLock
    $state = Get-StateDir
    $base = Get-ExportBase
    $pathspecs = @(Get-ExcludePathspecs)

    $out = Join-Path $state ("dotfiles-sync-$label-{0}.patch" -f (Get-Date -Format "yyyyMMdd'T'HHmmss"))
    $chunk = [IO.Path]::GetTempFileName()
    $subjects = [Collections.Generic.List[string]]::new()
    $stream = [IO.File]::Open($out, 'Create', 'Write', 'None')
    try {
        $created = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        Write-StreamText $stream "$($script:PatchHeader)`n# from: $label`n# created: $created`n"
        $commits = @(Invoke-Git -GitArgs @('rev-list', '--reverse', '--first-parent', "$base..HEAD") | Where-Object { $_ })
        foreach ($c in $commits) {
            # commits that were themselves imported from the peer go no further
            if (Get-SyncTrailer $c) { continue }
            $null = Invoke-Git -GitArgs (@('diff', '--binary', '--full-index', "--output=$chunk", "$c^1", $c, '--', '.') + $pathspecs)
            if ((Get-Item -LiteralPath $chunk).Length -eq 0) { continue }
            $subject = [string](Invoke-Git -GitArgs @('log', '-1', '--format=%s', $c))
            Write-StreamText $stream "=== change $c ===`nSubject: $subject`n"
            $bytes = [IO.File]::ReadAllBytes($chunk)
            $stream.Write($bytes, 0, $bytes.Length)
            $subjects.Add($subject)
        }
    }
    finally {
        $stream.Dispose()
        Remove-Item -LiteralPath $chunk -Force -ErrorAction SilentlyContinue
    }

    $head = ([string](Invoke-Git -GitArgs @('rev-parse', 'HEAD'))).Trim()
    if ($subjects.Count -eq 0) {
        Remove-Item -LiteralPath $out -Force
        Write-StateFile (Join-Path $state 'last-export') $head
        Write-Info 'nothing to send'
        return $true
    }

    Write-Info "$($subjects.Count) change(s) since $(Invoke-Git -GitArgs @('log', '-1', '--format=%h', $base)):"
    $subjects | ForEach-Object { [Console]::Error.WriteLine("  - $_") }
    if (-not (Test-OutgoingClean $out)) {
        Remove-Item -LiteralPath $out -Force
        return $false
    }

    if (-not $yes) {
        if ((Read-Answer 'Review the full patch in a pager first? [Y/n]') -notmatch '^[nN]$') { Show-InPager $out }
        if ((Read-Answer "Send these $($subjects.Count) change(s)? [y/N]") -notmatch '^[yY]$') {
            Remove-Item -LiteralPath $out -Force
            Write-Info 'not sent'
            return $true
        }
    }

    # once queued, the patch is the peer's copy of these commits: later runs
    # start after them and a failed send is retried from the outbox
    Write-StateFile (Join-Path $state 'last-export') $head
    return (Submit-SyncFile -File $out -Keep:$keep)
}

<#
.SYNOPSIS
    Sends every non-ignored tracked file as a tarball, for the first sync when
    the two repos have drifted apart.
.PARAMETER Arguments
    [--no-send] [--yes]
#>
function Invoke-Snapshot {
    param([string[]]$Arguments)
    $keep = $false; $yes = $false
    foreach ($a in $Arguments) {
        switch ($a) {
            '--no-send' { $keep = $true }
            '--yes' { $yes = $true }
            default { Stop-Sync "snapshot: unknown option $a" }
        }
    }
    $label = Get-SyncConfig label
    if (-not $label) { Stop-Sync 'not set up: dotfiles-sync setup --label NAME --peer DEVICE' }
    Assert-SyncLock
    $state = Get-StateDir
    $tar = Get-TarPath
    $out = Join-Path $state ("dotfiles-sync-$label-{0}.snapshot.tar" -f (Get-Date -Format "yyyyMMdd'T'HHmmss"))
    $null = Invoke-Git -GitArgs (@('archive', '--format=tar', "--output=$out", 'HEAD', '--', '.') + @(Get-ExcludePathspecs))

    $tmp = New-TempDir
    try {
        & $tar -x -f $out -C $tmp
        if ($LASTEXITCODE -ne 0) { Stop-Sync "could not unpack $out for the secret scan" }
        if (-not (Test-OutgoingClean $tmp)) {
            Remove-Item -LiteralPath $out -Force
            Stop-Sync 'snapshot not sent'
        }
        $count = @(Get-ChildItem -LiteralPath $tmp -Recurse -File -Force).Count
    }
    finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Info "snapshot of $count files at $(Invoke-Git -GitArgs @('log', '-1', '--format=%h', 'HEAD'))"
    if (-not $yes -and (Read-Answer 'Send it? [y/N]') -notmatch '^[yY]$') {
        Remove-Item -LiteralPath $out -Force
        Write-Info 'not sent'
        return
    }
    $null = Submit-SyncFile -File $out -Keep:$keep
}

<#
.SYNOPSIS
    Creates and returns a new empty temporary directory.
#>
function New-TempDir {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-sync-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $dir
    return $dir
}

<#
.SYNOPSIS
    Moves files Taildrop delivered (its inbox, the Downloads folder) into
    .git\dotfiles-sync\inbox\.
#>
function Receive-Incoming {
    $inbox = Join-Path (Get-StateDir) 'inbox'
    $ts = Get-TailscalePath
    if ($ts) {
        try { & $ts file get --conflict=rename $inbox *> $null } catch { }
    }
    foreach ($dl in Get-DownloadDirs) {
        if (-not (Test-Path -LiteralPath $dl -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $dl -File -Filter 'dotfiles-sync-*' |
            Where-Object { $_.Name -like '*.patch' -or $_.Name -like '*.snapshot.tar' } |
            ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $inbox -Force }
    }
}

<#
.SYNOPSIS
    Returns the incoming files to work through, oldest first: held ones before
    new ones (unless -NewOnly), or the paths given on the command line.
.PARAMETER Files
    Explicit files.
.PARAMETER NewOnly
    Leave held files out.
#>
function Get-IncomingFiles {
    param([string[]]$Files, [switch]$NewOnly)
    if ($Files -and $Files.Count -gt 0) {
        return @($Files | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
    }
    $state = Get-StateDir
    Receive-Incoming
    $list = [Collections.Generic.List[string]]::new()
    if (-not $NewOnly) {
        Get-ChildItem -LiteralPath (Join-Path $state 'inbox\held') -File -Filter 'dotfiles-sync-*' |
            Sort-Object Name | ForEach-Object { $list.Add($_.FullName) }
    }
    Get-ChildItem -LiteralPath (Join-Path $state 'inbox') -File -Filter 'dotfiles-sync-*' |
        Sort-Object Name | ForEach-Object { $list.Add($_.FullName) }
    return $list.ToArray()
}

<#
.SYNOPSIS
    Lays a snapshot's files over the working tree for review. This repo's own
    .syncignore still applies: matching paths are dropped from the unpacked copy
    first ("/x" is taken relative to the snapshot root, "!" patterns are
    ignored, and nothing outside the temporary copy is touched).
.PARAMETER File
    Snapshot tarball.
#>
function Import-Snapshot {
    param([Parameter(Mandatory)][string]$File)
    $tar = Get-TarPath
    $tmp = New-TempDir
    $pruned = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-sync-" + [guid]::NewGuid().ToString('N') + '.tar')
    try {
        & $tar -x -f $File -C $tmp
        if ($LASTEXITCODE -ne 0) { Stop-Sync "could not unpack $File" }
        $root = (Resolve-Path -LiteralPath $tmp).Path.TrimEnd('\') + '\'
        foreach ($p in Get-SyncIgnorePatterns) {
            if ($p.StartsWith('!')) { continue }
            $p = $p.TrimStart('/').TrimEnd('/')
            if (-not $p) { continue }
            foreach ($m in @(Get-Item -Path (Join-Path $tmp $p) -Force -ErrorAction SilentlyContinue)) {
                if (-not $m.FullName.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { continue }
                Remove-Item -LiteralPath $m.FullName -Recurse -Force
            }
        }
        & $tar -c -f $pruned -C $tmp .
        if ($LASTEXITCODE -ne 0) { Stop-Sync 'could not repack the snapshot' }
        & $tar -x -f $pruned -C $script:Repo
        if ($LASTEXITCODE -ne 0) { Stop-Sync 'could not unpack the snapshot over the working tree' }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $pruned -Force -ErrorAction SilentlyContinue
    }
    Write-Info "snapshot laid over the working tree. Review with 'git -C $($script:Repo) diff' and"
    Write-Info "'git -C $($script:Repo) add -p' (new files: git status), commit what you keep,"
    Write-Info "discard the rest, then run 'dotfiles-sync baseline' on BOTH machines."
}

<#
.SYNOPSIS
    Splits a patch file into its changes, byte for byte.
.PARAMETER File
    Patch file.
.OUTPUTS
    Objects with Sha, Subject (decoded as UTF-8) and Body (Latin-1 string of the
    diff, to be written back with Latin-1), plus a From property on the first.
#>
function Split-SyncPatch {
    param([Parameter(Mandatory)][string]$File)
    $text = $script:Latin1.GetString([IO.File]::ReadAllBytes($File))
    $lines = $text.Split("`n")
    # like awk: a trailing newline does not start another (empty) line
    $count = if ($text.EndsWith("`n")) { $lines.Length - 1 } else { $lines.Length }
    $changes = [Collections.Generic.List[object]]::new()
    $current = $null
    $sb = $null
    for ($i = 0; $i -lt $count; $i++) {
        $line = $lines[$i]
        if ($line -match '^=== change ([0-9a-f]+) ===$') {
            if ($current) { $current.Body = $sb.ToString(); $changes.Add($current) }
            $current = [pscustomobject]@{ Sha = $Matches[1]; Subject = ''; Body = '' }
            $sb = [Text.StringBuilder]::new()
            if ($i + 1 -lt $count -and $lines[$i + 1].StartsWith('Subject: ')) {
                $raw = $lines[$i + 1].Substring(9)
                $current.Subject = $script:Utf8.GetString($script:Latin1.GetBytes($raw))
                $i++
            }
            continue
        }
        if ($current) { $null = $sb.Append($line).Append("`n") }
    }
    if ($current) { $current.Body = $sb.ToString(); $changes.Add($current) }
    return $changes.ToArray()
}

<#
.SYNOPSIS
    Walks the changes in one patch file. Interactively it asks to apply or skip
    each one; with -Auto it applies them all and stops at the first that does
    not apply cleanly. Applied changes are committed with the trailer.
.PARAMETER File
    Patch file.
.PARAMETER Auto
    Apply without asking.
.OUTPUTS
    0 when every change was handled, 1 when stopped early (quit, or not a
    patch), 2 when -Auto hit a change that needs a human.
#>
function Import-SyncPatch {
    param([Parameter(Mandatory)][string]$File, [switch]$Auto)
    $state = Get-StateDir
    # read the header with ReadAllBytes: a ReadLines enumerator left undisposed
    # keeps the file open, and the patch is moved to inbox\done afterwards
    $headerLines = $script:Latin1.GetString([IO.File]::ReadAllBytes($File)).Split("`n", 4)
    if ($headerLines[0] -ne $script:PatchHeader) { Write-Info "not a dotfiles-sync patch: $File"; return 1 }
    $from = ''
    foreach ($l in $headerLines | Select-Object -First 3) {
        if ($l -match '^# from: (.*)$') { $from = $Matches[1]; break }
    }
    if ($from -eq (Get-SyncConfig label)) { Write-Info "skipping ${File}: it came from this side"; return 0 }

    $applyOpts = @(Get-ExcludeApplyOptions)
    $fmt = "--format=%(trailers:key=$($script:Trailer),valueonly)"
    $done = [Collections.Generic.HashSet[string]]::new([string[]]@(Invoke-Git -GitArgs @('log', $fmt, 'HEAD') | Where-Object { $_ }))
    $skippedFile = Join-Path $state 'skipped'
    if (-not (Test-Path -LiteralPath $skippedFile)) { [IO.File]::WriteAllText($skippedFile, '') }
    $skipped = [Collections.Generic.HashSet[string]]::new([string[]]@(Get-PatternLines $skippedFile))

    $body = [IO.Path]::GetTempFileName()
    try {
        foreach ($change in Split-SyncPatch $File) {
            $key = "$from $($change.Sha)"
            if ($done.Contains($key) -or $skipped.Contains($key)) { continue }
            [IO.File]::WriteAllText($body, $change.Body, $script:Latin1)
            $shortSha = $change.Sha.Substring(0, [Math]::Min(10, $change.Sha.Length))
            $message = "sync(${from}): $($change.Subject)"

            if ($Auto) {
                & git -C $script:Repo apply --3way --index --whitespace=nowarn @applyOpts $body 2>&1 |
                    ForEach-Object { [Console]::Error.WriteLine([string]$_) }
                if ($LASTEXITCODE -ne 0) {
                    # the cycle started from a clean, committed tree: drop the partial apply
                    $null = Invoke-Git -GitArgs @('reset', '-q', '--hard', 'HEAD')
                    Write-Info "change from $from does not apply cleanly: $($change.Subject) ($shortSha)"
                    return 2
                }
                if (Test-Git @('diff', '--cached', '--quiet')) {
                    Write-Info "already present or ignored here: $($change.Subject)"
                    Write-StateFile $skippedFile $key -Append
                }
                else {
                    $null = Invoke-Git -GitArgs @('commit', '-q', '-m', $message, '-m', "$($script:Trailer): $key")
                    Write-Info "applied from ${from}: $($change.Subject) ($(Invoke-Git -GitArgs @('log', '-1', '--format=%h')))"
                }
                continue
            }

            $handled = $false
            while (-not $handled) {
                Write-Host "`n--- from ${from}: $($change.Subject) ($shortSha)"
                & git -C $script:Repo apply --stat @applyOpts $body 2>&1 | ForEach-Object { Write-Host ([string]$_) }
                $answer = Read-Answer 'Apply? [y]es / [n]o, skip for good / [s]how diff / [q]uit'
                if ($answer -match '^[sS]$') { Show-InPager $body }
                elseif ($answer -match '^[nN]$') { Write-StateFile $skippedFile $key -Append; $handled = $true }
                elseif ($answer -match '^[qQ]$') { return 1 }
                elseif ($answer -match '^[yY]$') {
                    & git -C $script:Repo apply --3way --index --whitespace=nowarn @applyOpts $body 2>&1 |
                        ForEach-Object { Write-Host ([string]$_) }
                    if ($LASTEXITCODE -ne 0) {
                        if ((Test-Git @('diff', '--quiet')) -and (Test-Git @('diff', '--cached', '--quiet'))) {
                            Write-Info 'this change does not apply here (the files differ too much); answer n to skip it'
                            continue
                        }
                        # tells 'auto' not to commit the half-resolved tree without the trailer
                        Write-StateFile (Join-Path $state 'resolving') $key
                        Write-Info "applied with conflicts. Resolve them, 'git add' the files, then run:"
                        Write-Info "  git -C $($script:Repo) commit -m `"$($message -replace '"', '\"')`" -m `"$($script:Trailer): $key`""
                        Write-Info "and rerun 'dotfiles-sync import' for the rest."
                        Stop-Sync 'import stopped at a conflict'
                    }
                    if (Test-Git @('diff', '--cached', '--quiet')) {
                        Write-Info 'nothing left to change (already present or ignored here)'
                        Write-StateFile $skippedFile $key -Append
                    }
                    else {
                        $null = Invoke-Git -GitArgs @('commit', '-q', '-m', $message, '-m', "$($script:Trailer): $key")
                        Write-Info "committed $(Invoke-Git -GitArgs @('log', '-1', '--format=%h'))"
                    }
                    $handled = $true
                }
            }
        }
    }
    finally { Remove-Item -LiteralPath $body -Force -ErrorAction SilentlyContinue }
    return 0
}

<#
.SYNOPSIS
    Applies what the peer sent. Interactively it also works through files held
    by an earlier unattended run; with --auto it pauses while anything is held,
    applies patches without asking, and holds (with a notification) snapshots
    and patches that do not apply cleanly.
.PARAMETER Arguments
    [--auto] [explicit patch/snapshot files] (default: Taildrop inbox).
#>
function Invoke-Import {
    param([string[]]$Arguments)
    $auto = $false
    $files = @($Arguments)
    if ($files.Count -gt 0 -and $files[0] -eq '--auto') { $auto = $true; $files = @($files | Select-Object -Skip 1) }
    if (-not (Get-SyncConfig label)) { Stop-Sync 'not set up: dotfiles-sync setup --label NAME --peer DEVICE' }
    Assert-SyncLock
    if (-not ((Test-Git @('diff', '--quiet')) -and (Test-Git @('diff', '--cached', '--quiet')))) {
        Stop-Sync 'the repo has uncommitted changes to tracked files; commit or stash them first'
    }
    $state = Get-StateDir
    $heldDir = Join-Path $state 'inbox\held'
    $inboxDir = Join-Path $state 'inbox'

    if ($auto -and $files.Count -eq 0) {
        $held = @(Get-ChildItem -LiteralPath $heldDir -File -Filter 'dotfiles-sync-*').Count
        if ($held -gt 0) {
            Receive-Incoming
            Write-Info "$held held file(s) wait for an interactive 'dotfiles-sync import'; not applying anything new"
            $script:LastRunStatus = 'held'
            return
        }
    }

    $incoming = @(Get-IncomingFiles -Files $files -NewOnly:$auto)
    if ($incoming.Count -eq 0) { Write-Info 'nothing received'; return }
    foreach ($f in $incoming) {
        $name = Split-Path -Leaf $f
        $parent = (Split-Path -Parent $f).TrimEnd('\')
        Write-Info "incoming: $name"
        if ($name -like '*.snapshot.tar') {
            if ($auto) {
                Move-Item -LiteralPath $f -Destination $heldDir -Force
                Send-SyncNotification 'dotfiles-sync' "A snapshot arrived ($name). Run 'dotfiles-sync import' to review it."
                $script:LastRunStatus = 'held'
                $script:LastRunMsg = "snapshot $name held"
                return
            }
            Import-Snapshot $f
            Move-Item -LiteralPath $f -Destination (Join-Path $state 'inbox\done') -Force -ErrorAction SilentlyContinue
            return
        }
        $rc = Import-SyncPatch -File $f -Auto:$auto
        switch ($rc) {
            0 {
                if ($parent -eq $inboxDir -or $parent -eq $heldDir) {
                    Move-Item -LiteralPath $f -Destination (Join-Path $state 'inbox\done') -Force
                }
            }
            2 {
                if ($parent -eq $inboxDir) { Move-Item -LiteralPath $f -Destination $heldDir -Force }
                Send-SyncNotification 'dotfiles-sync' "A change in $name conflicts with this repo. Run 'dotfiles-sync import' to resolve it."
                $script:LastRunStatus = 'held'
                $script:LastRunMsg = "conflict in $name"
                return
            }
            default { return }
        }
    }
}

<#
.SYNOPSIS
    Sends whatever is still queued in the outbox.
#>
function Invoke-Flush {
    Assert-SyncLock
    if (-not (Send-Outbox)) { Stop-Sync 'some files are still queued' }
}

<#
.SYNOPSIS
    One unattended cycle: commit local changes, apply what the peer sent, send
    what is new, retry anything still queued. Skips quietly while another run
    holds the lock, a merge/rebase is in progress, or an interactive import is
    waiting for its conflicts to be committed.
#>
function Invoke-Auto {
    if (-not (Get-SyncConfig label)) { Stop-Sync 'not set up: dotfiles-sync setup --label NAME --peer DEVICE' }
    if (-not (Enter-SyncLock 0)) {
        Write-Info 'another dotfiles-sync run holds the lock; skipping this cycle'
        return
    }
    $script:AutoRun = $true
    $state = Get-StateDir
    $gitDir = [string](Invoke-Git -GitArgs @('rev-parse', '--absolute-git-dir'))

    $busy = (Test-Path (Join-Path $gitDir 'MERGE_HEAD')) -or (Test-Path (Join-Path $gitDir 'rebase-merge')) -or
        (Test-Path (Join-Path $gitDir 'rebase-apply')) -or (Test-Path (Join-Path $gitDir 'CHERRY_PICK_HEAD')) -or
        [bool](Invoke-Git -GitArgs @('ls-files', '-u'))
    if ($busy) {
        $script:LastRunStatus = 'skipped'
        $script:LastRunMsg = 'merge, rebase or conflict in progress'
        Write-Info 'a merge, rebase or conflict is in progress; skipping this cycle'
        return
    }
    $resolving = Join-Path $state 'resolving'
    if (Test-Path -LiteralPath $resolving) {
        if (Invoke-Git -GitArgs @('status', '--porcelain')) {
            $script:LastRunStatus = 'skipped'
            $script:LastRunMsg = 'waiting for the conflicted import to be committed'
            Write-Info 'an interactive import is being resolved; skipping this cycle'
            return
        }
        Remove-Item -LiteralPath $resolving -Force
    }

    # 1. local changes become a commit made with this repo's own identity
    if (Invoke-Git -GitArgs @('status', '--porcelain')) {
        $null = Invoke-Git -GitArgs @('add', '-A')
        $null = Invoke-Git -GitArgs @('commit', '-q', '-m', $script:AutoCommitMsg)
        Write-Info "committed local changes ($(Invoke-Git -GitArgs @('log', '-1', '--format=%h')))"
    }

    # 2. apply what arrived
    Invoke-Import @('--auto')

    # 3. send what is new, and whatever an earlier run could not send
    $ok = Invoke-Export @('--yes')
    $head = ([string](Invoke-Git -GitArgs @('rev-parse', 'HEAD'))).Trim()
    $blockedFile = Join-Path $state 'scan-blocked'
    if (-not $ok -and (Read-StateFile (Join-Path $state 'last-export')) -ne $head) {
        # export only fails before queueing when the secret scan blocked it
        $script:LastRunStatus = 'blocked'
        $script:LastRunMsg = 'outgoing changes failed the secret scan'
        if ((Read-StateFile $blockedFile) -ne $head) {
            Write-StateFile $blockedFile $head
            Send-SyncNotification 'dotfiles-sync' "Outgoing changes match a secret or blocklist pattern and were not sent. See $(Join-Path $state 'sync.log')."
        }
        $null = Send-Outbox
    }
    elseif (-not $ok) {
        Remove-Item -LiteralPath $blockedFile -Force -ErrorAction SilentlyContinue
        if (-not $script:LastRunStatus) { $script:LastRunStatus = 'queued' }
        if (-not $script:LastRunMsg) { $script:LastRunMsg = "$(@(Get-QueuedFiles).Count) file(s) waiting for the peer" }
    }
    else {
        Remove-Item -LiteralPath $blockedFile -Force -ErrorAction SilentlyContinue
    }

    # 4. retry what earlier runs could not send (export only sends when it queued something)
    if (@(Get-QueuedFiles).Count -gt 0 -and -not (Send-Outbox)) {
        if (-not $script:LastRunStatus) { $script:LastRunStatus = 'queued' }
        if (-not $script:LastRunMsg) { $script:LastRunMsg = "$(@(Get-QueuedFiles).Count) file(s) waiting for the peer" }
    }
}

<#
.SYNOPSIS
    Runs one 'auto' cycle in a child process, so a failure or a stuck git call
    never takes the watcher down and the lock is always released.
#>
function Start-AutoCycle {
    $pwsh = (Get-Process -Id $PID).Path
    & $pwsh -NoProfile -NonInteractive -File $PSCommandPath -C $script:Repo auto
    if ($LASTEXITCODE -ne 0) { Write-SyncLog "auto cycle exited with $LASTEXITCODE" }
}

<#
.SYNOPSIS
    Watches the repo and runs 'auto' once changes have settled, plus on a
    fixed poll interval (to pick up incoming files and retry queued sends).
.PARAMETER Arguments
    [--debounce SECONDS] [--poll SECONDS] [--max-wait SECONDS]
#>
function Invoke-Watch {
    param([string[]]$Arguments)
    $debounce = 120; $poll = 300; $maxWait = 600
    for ($i = 0; $i -lt $Arguments.Count; $i += 2) {
        if ($i + 1 -ge $Arguments.Count) { Stop-Sync "watch: $($Arguments[$i]) needs a value" }
        $value = [int]$Arguments[$i + 1]
        switch ($Arguments[$i]) {
            '--debounce' { $debounce = $value }
            '--poll' { $poll = $value }
            '--max-wait' { $maxWait = $value }
            default { Stop-Sync "watch: unknown option $($Arguments[$i])" }
        }
    }
    if (-not (Get-SyncConfig label)) { Stop-Sync 'not set up: dotfiles-sync setup --label NAME --peer DEVICE' }

    $gitDirPrefix = (Join-Path ($script:Repo -replace '/', '\') '.git').TrimEnd('\') + '\'
    $watcher = [IO.FileSystemWatcher]::new(($script:Repo -replace '/', '\'))
    $watcher.IncludeSubdirectories = $true
    $watcher.InternalBufferSize = 65536
    $watcher.NotifyFilter = [IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size'
    $sources = foreach ($evt in 'Changed', 'Created', 'Deleted', 'Renamed', 'Error') {
        $id = "dotfiles-sync.$evt"
        $null = Register-ObjectEvent -InputObject $watcher -EventName $evt -SourceIdentifier $id
        $id
    }
    $watcher.EnableRaisingEvents = $true
    Write-Info "watching $($script:Repo) (debounce ${debounce}s, poll ${poll}s)"

    $firstChange = $null; $lastChange = $null
    $nextPoll = (Get-Date).AddSeconds(5)   # one cycle right after start
    try {
        while ($true) {
            $now = Get-Date
            $due = $nextPoll
            if ($lastChange) {
                $settle = $lastChange.AddSeconds($debounce)
                $cap = $firstChange.AddSeconds($maxWait)
                $changeDue = if ($settle -lt $cap) { $settle } else { $cap }
                if ($changeDue -lt $due) { $due = $changeDue }
            }
            $wait = [int][Math]::Max(1, [Math]::Ceiling(($due - $now).TotalSeconds))
            $evt = Wait-Event -Timeout $wait
            while ($evt) {
                $path = [string]$evt.SourceEventArgs.FullPath
                $isError = $evt.SourceIdentifier -eq 'dotfiles-sync.Error'
                if ($isError -or -not $path.StartsWith($gitDirPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    $lastChange = Get-Date
                    if (-not $firstChange) { $firstChange = $lastChange }
                }
                Remove-Event -EventIdentifier $evt.EventIdentifier
                $evt = Get-Event | Select-Object -First 1
            }

            $now = Get-Date
            $runNow = $false
            if ($lastChange -and ($now -ge $lastChange.AddSeconds($debounce) -or $now -ge $firstChange.AddSeconds($maxWait))) {
                $firstChange = $null; $lastChange = $null
                # churn in gitignored files ends here, without a full cycle
                if (Invoke-Git -GitArgs @('status', '--porcelain') -AllowFail) { $runNow = $true }
            }
            if ($now -ge $nextPoll) { $runNow = $true }
            if ($runNow) {
                try { Start-AutoCycle } catch { Write-SyncLog "auto cycle failed: $($_.Exception.Message)" }
                $nextPoll = (Get-Date).AddSeconds($poll)
            }
        }
    }
    finally {
        $watcher.EnableRaisingEvents = $false
        foreach ($id in $sources) { Unregister-Event -SourceIdentifier $id -ErrorAction SilentlyContinue }
        $watcher.Dispose()
    }
}

<#
.SYNOPSIS
    Registers the Task Scheduler tasks for continuous sync: DotfilesSyncWatch
    ('watch', at logon, restarted on failure) and DotfilesSyncTick ('auto'
    every 15 minutes as a fallback). Both run hidden, as the current user.
#>
function Invoke-Schedule {
    if (-not (Get-SyncConfig label)) { Stop-Sync 'not set up: dotfiles-sync setup --label NAME --peer DEVICE' }
    $pwsh = (Get-Process -Id $PID).Path
    # a Store-installed pwsh runs from a versioned folder that goes away on
    # update; its app execution alias keeps working across updates
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
    if ($pwsh -like '*\WindowsApps\Microsoft.PowerShell_*' -and (Test-Path -LiteralPath $alias)) { $pwsh = $alias }
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $repoWin = $script:Repo -replace '/', '\'
    $scriptArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`" -C `"$repoWin`""
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

    # conhost --headless runs the console app without ever showing a window
    $watchAction = New-ScheduledTaskAction -Execute $conhost -Argument "--headless `"$pwsh`" $scriptArgs watch" -WorkingDirectory $repoWin
    $watchTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $watchSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    $null = Register-ScheduledTask -TaskName $script:WatchTaskName -Action $watchAction -Trigger $watchTrigger `
        -Settings $watchSettings -Principal $principal -Description 'dotfiles-sync: watch the repo and sync with the peer' -Force

    $tickAction = New-ScheduledTaskAction -Execute $conhost -Argument "--headless `"$pwsh`" $scriptArgs auto" -WorkingDirectory $repoWin
    $tickTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
    $tickSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
    $null = Register-ScheduledTask -TaskName $script:TickTaskName -Action $tickAction -Trigger $tickTrigger `
        -Settings $tickSettings -Principal $principal -Description 'dotfiles-sync: fallback sync every 15 minutes' -Force

    Start-ScheduledTask -TaskName $script:WatchTaskName
    Write-Info "scheduled tasks $($script:WatchTaskName) (at logon, started now) and $($script:TickTaskName) (every 15 minutes)"
}

<#
.SYNOPSIS
    Stops and removes the Task Scheduler tasks registered by 'schedule'.
#>
function Invoke-Unschedule {
    foreach ($name in $script:WatchTaskName, $script:TickTaskName) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Info "removed scheduled task $name"
        }
    }
}

<#
.SYNOPSIS
    Shows this side's sync settings and what is waiting in each direction.
#>
function Show-Status {
    $state = Get-StateDir
    $base = Read-StateFile (Join-Path $state 'last-export')
    $rows = [ordered]@{
        'repo'  = $script:Repo
        'label' = Get-SyncConfig label
        'peer'  = Get-SyncConfig peer
        'email' = Get-SyncConfig email
    }
    if ($base) {
        try { $base = Get-ExportBase } catch { }
        $pathspecs = @(Get-ExcludePathspecs)
        $pending = 0
        $commits = @(Invoke-Git -GitArgs @('rev-list', '--first-parent', "$base..HEAD") -AllowFail -Quiet | Where-Object { $_ })
        foreach ($c in $commits) {
            if (Get-SyncTrailer $c) { continue }
            if (-not (Test-Git (@('diff', '--quiet', "$c^1", $c, '--', '.') + $pathspecs))) { $pending++ }
        }
        $desc = Invoke-Git -GitArgs @('log', '-1', '--format=%h %s', $base) -AllowFail -Quiet
        $rows['baseline'] = if ($LASTEXITCODE -eq 0) { [string]$desc } else { "$base (missing)" }
        $rows['to send'] = "$pending commit(s)"
    }
    else { $rows['baseline'] = '(none)' }
    $count = { param($dir) @(Get-ChildItem -LiteralPath (Join-Path $state $dir) -File -Filter 'dotfiles-sync-*').Count }
    $rows['queued'] = "$(& $count 'outbox') file(s) in outbox"
    $rows['inbox'] = "$(& $count 'inbox') file(s)"
    $held = & $count 'inbox\held'
    $rows['held'] = "$held file(s)" + $(if ($held -gt 0) { ' - run dotfiles-sync import' } else { '' })
    $last = Read-StateFile (Join-Path $state 'last-run')
    $rows['last run'] = if ($last) { $last } else { '(never)' }
    $task = Get-ScheduledTask -TaskName $script:WatchTaskName -ErrorAction SilentlyContinue
    $rows['watcher'] = if ($task) { "$($task.State) (task $($script:WatchTaskName))" } else { 'not scheduled (dotfiles-sync schedule)' }
    foreach ($k in $rows.Keys) { Write-Output ('{0,-10} {1}' -f "${k}:", $rows[$k]) }
}

<#
.SYNOPSIS
    Prints the usage text.
#>
function Show-Usage {
    @'
dotfiles-sync - keep two dotfiles repos in sync by content, never by history.

  dotfiles-sync setup --label NAME --peer DEVICE [--email REGEX]
  dotfiles-sync export [--no-send] [--yes]    send new commits to the peer
  dotfiles-sync import [--auto] [FILE...]     review and apply what arrived
  dotfiles-sync snapshot [--no-send] [--yes]  send every file (first sync)
  dotfiles-sync baseline [COMMIT]             mark COMMIT (default HEAD) as synced
  dotfiles-sync flush                         send patches still queued in the outbox
  dotfiles-sync auto                          one unattended sync cycle
  dotfiles-sync watch [--debounce S] [--poll S] [--max-wait S]
  dotfiles-sync schedule | unschedule         run 'watch' at logon (+ 15-min fallback)
  dotfiles-sync status

Options go before the command: -C DIR selects the repo (default ~\dotfiles or
$env:DOTFILES_SYNC_REPO). Full details: Get-Help scripts\dotfiles-sync.ps1 -Full
'@
}

# --- main ----------------------------------------------------------------------

<#
.SYNOPSIS
    Parses the command line and runs the command, setting $script:ExitCode.
.PARAMETER Argv
    The script's arguments.
#>
function Invoke-Main {
    param([string[]]$Argv)
    $argList = [Collections.Generic.List[string]]::new()
    if ($Argv) { $argList.AddRange([string[]]$Argv) }
    if ($argList.Count -ge 2 -and $argList[0] -eq '-C') {
        $script:Repo = $argList[1]
        $argList.RemoveRange(0, 2)
    }
    $command = if ($argList.Count -gt 0) { $argList[0] } else { 'status' }
    # typed variable: an 'if' expression would unwrap a single argument into a plain string
    [string[]]$rest = @($argList | Select-Object -Skip 1)

    if ($command -in '-h', '--help', 'help') { Show-Usage; return }
    try {
        if (-not (Test-Path -LiteralPath $script:Repo -PathType Container)) {
            Stop-Sync "repo not found: $($script:Repo) (set `$env:DOTFILES_SYNC_REPO or pass -C DIR)"
        }
        $top = & git -C $script:Repo rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0) { Stop-Sync "not a git repo: $($script:Repo)" }
        $script:Repo = ([string]$top).Trim()
        if ($command -ne 'check-push') { $script:SyncLog = Join-Path (Get-StateDir) 'sync.log' }

        switch ($command) {
            'setup' { Invoke-Setup $rest }
            'export' { if (-not (Invoke-Export $rest)) { $script:ExitCode = 1 } }
            'import' { Invoke-Import $rest }
            'snapshot' { Invoke-Snapshot $rest }
            'baseline' { if ($rest.Count -gt 0) { Invoke-Baseline $rest[0] } else { Invoke-Baseline } }
            'flush' { Invoke-Flush }
            'auto' { Invoke-Auto }
            'watch' { Invoke-Watch $rest }
            'schedule' { Invoke-Schedule }
            'unschedule' { Invoke-Unschedule }
            'status' { Show-Status }
            'check-push' { $script:ExitCode = Invoke-CheckPush $rest }
            default { Stop-Sync "unknown command: $command (try --help)" }
        }
        return
    }
    catch {
        if ($script:AutoRun) {
            $script:LastRunStatus = 'error'
            $script:LastRunMsg = $_.Exception.Message
        }
        if ($_.Exception.Data['dotfiles-sync']) {
            [Console]::Error.WriteLine("dotfiles-sync: $($_.Exception.Message)")
            Write-SyncLog "error: $($_.Exception.Message)"
        }
        else {
            [Console]::Error.WriteLine("dotfiles-sync: $($_.Exception.Message)")
            [Console]::Error.WriteLine($_.ScriptStackTrace)
            Write-SyncLog "error: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)"
        }
        $script:ExitCode = 1
    }
    finally {
        if ($script:AutoRun) {
            try {
                $status = if ($script:LastRunStatus) { $script:LastRunStatus } else { 'ok' }
                $stamp = Get-Date -Format "yyyy-MM-dd'T'HH:mm:sszzz"
                Write-StateFile (Join-Path (Get-StateDir) 'last-run') ("$stamp $status $($script:LastRunMsg)".TrimEnd())
            }
            catch { }
        }
        Exit-SyncLock
    }
}

Invoke-Main $args
exit $script:ExitCode
