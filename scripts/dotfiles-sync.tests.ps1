#Requires -Version 7.0
<#
.SYNOPSIS
    Interop tests for dotfiles-sync: the bash script (scripts/dotfiles-sync.sh,
    run in Git for Windows' bash) and the PowerShell port
    (scripts/dotfiles-sync.ps1) syncing two throwaway repos with each other.

.DESCRIPTION
    Repo A plays the Mac (bash, label "personal"), repo B the Windows machine
    (PowerShell, label "work"). A fake tailscale CLI moves files between
    per-device drop folders, so nothing touches the real tailnet, and the
    Downloads folders are redirected, so nothing touches the real ones.

    Runs without Pester; prints PASS/FAIL per check and exits non-zero on any
    failure. Everything lives under a temp directory that is removed at the end
    (pass -Keep to leave it for inspection).

.PARAMETER Keep
    Keep the temp directory.

.EXAMPLE
    pwsh -NoProfile -File scripts\dotfiles-sync.tests.ps1
#>
param([switch]$Keep)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

<# Path of the PowerShell implementation under test. #>
$script:Ps1 = Join-Path $PSScriptRoot 'dotfiles-sync.ps1'
<# Path of the bash implementation under test, forward slashes for bash. #>
$script:Sh = (Join-Path $PSScriptRoot 'dotfiles-sync.sh') -replace '\\', '/'
<# Git for Windows' bash.exe. #>
$script:Bash = @(
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')
    $(if (Get-Command git -ErrorAction SilentlyContinue) { Join-Path (Split-Path (Split-Path (Get-Command git).Source)) 'bin\bash.exe' })
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
<# Temp root holding both repos, the drop folders and the fakes. #>
$script:Root = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-sync-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
<# Number of failed checks. #>
$script:Failures = 0
<# Number of passed checks. #>
$script:Passes = 0

<#
.SYNOPSIS
    Records one check.
.PARAMETER Condition
    Whether the check passed.
.PARAMETER Name
    What was checked.
.PARAMETER Detail
    Extra output shown on failure.
#>
function Assert-That {
    param([bool]$Condition, [string]$Name, [string]$Detail = '')
    if ($Condition) {
        $script:Passes++
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    else {
        $script:Failures++
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host ($Detail.Trim() -replace '(?m)^', '        ') -ForegroundColor DarkGray }
    }
}

<#
.SYNOPSIS
    Converts a Windows path to the /c/... form Git Bash uses.
.PARAMETER Path
    Windows path.
#>
function ConvertTo-PosixPath {
    param([string]$Path)
    $p = $Path -replace '\\', '/'
    if ($p -match '^([A-Za-z]):/(.*)$') { return "/$($Matches[1].ToLower())/$($Matches[2])" }
    return $p
}

<#
.SYNOPSIS
    Runs git in a test repo and returns its output.
    Takes the repo path first, then git's arguments (plain $args, so flags
    such as -r or -q are never mistaken for PowerShell parameters).
#>
function Invoke-TestGit {
    $Repo = [string]$args[0]
    $GitArgs = [string[]]@($args | Select-Object -Skip 1)
    $out = & git -C $Repo @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed in ${Repo}: $out" }
    return $out
}

<#
.SYNOPSIS
    Runs the PowerShell implementation against repo B ("work").
    Takes the command and its arguments as plain $args.
.OUTPUTS
    Object with Code (exit code) and Out (stdout and stderr text).
#>
function Invoke-B {
    $SyncArgs = [string[]]@($args)
    $env:FAKE_TS_SELF = 'b'
    $env:DOTFILES_SYNC_DOWNLOADS = $script:DownloadsB
    $out = & pwsh -NoProfile -NonInteractive -File $script:Ps1 -C $script:RepoB @SyncArgs 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

<#
.SYNOPSIS
    Runs the bash implementation against repo A ("personal").
    Takes the command and its arguments as plain $args.
.OUTPUTS
    Object with Code (exit code) and Out (stdout and stderr text).
#>
function Invoke-A {
    $SyncArgs = [string[]]@($args)
    $env:FAKE_TS_SELF = 'a'
    $env:DOTFILES_SYNC_DOWNLOADS = ConvertTo-PosixPath $script:DownloadsA
    $out = '' | & $script:Bash $script:Sh -C ($script:RepoA -replace '\\', '/') @SyncArgs 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

<#
.SYNOPSIS
    Returns path => blob id for HEAD of a repo, leaving out paths that never sync.
.PARAMETER Repo
    Repo path.
#>
function Get-SyncedTree {
    param([string]$Repo)
    $map = @{}
    foreach ($line in Invoke-TestGit $Repo ls-tree -r HEAD) {
        if ($line -match '^\S+ \S+ (\S+)\t(.*)$') {
            $path = $Matches[2]
            if ($path -eq '.syncignore' -or $path -like 'work-only/*' -or $path -eq 'anchored-only.txt' -or $path -eq 'leak.txt') { continue }
            $map[$path] = $Matches[1]
        }
    }
    return $map
}

<#
.SYNOPSIS
    Compares the synced part of both repos and returns a description of the
    differences ('' when identical).
#>
function Compare-Repos {
    $a = Get-SyncedTree $script:RepoA
    $b = Get-SyncedTree $script:RepoB
    $diff = foreach ($k in @($a.Keys) + @($b.Keys) | Sort-Object -Unique) {
        if ($a[$k] -ne $b[$k]) { "$k  A=$($a[$k])  B=$($b[$k])" }
    }
    return ($diff -join "`n")
}

<#
.SYNOPSIS
    Writes a file inside a test repo, creating folders as needed.
.PARAMETER Repo
    Repo path.
.PARAMETER Path
    Relative path.
.PARAMETER Content
    Text, or a byte array for binary content.
#>
function Set-RepoFile {
    param([string]$Repo, [string]$Path, $Content)
    $full = Join-Path $Repo $Path
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $full)
    if ($Content -is [byte[]]) { [IO.File]::WriteAllBytes($full, $Content) }
    else { [IO.File]::WriteAllText($full, [string]$Content, [Text.UTF8Encoding]::new($false)) }
}

<#
.SYNOPSIS
    Returns the files waiting in a fake Taildrop drop folder.
.PARAMETER Device
    "a" or "b".
#>
function Get-Dropped {
    param([string]$Device)
    $dir = Join-Path $script:Drop $Device
    if (-not (Test-Path $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -File)
}

<#
.SYNOPSIS
    Creates both repos with identical content, the fakes and the drop folders.
#>
function Initialize-TestBed {
    $script:RepoA = Join-Path $script:Root 'a'
    $script:RepoB = Join-Path $script:Root 'b'
    $script:Drop = Join-Path $script:Root 'drop'
    $script:DownloadsA = Join-Path $script:Root 'downloads-a'
    $script:DownloadsB = Join-Path $script:Root 'downloads-b'
    foreach ($d in $script:RepoA, $script:RepoB, $script:Drop, $script:DownloadsA, $script:DownloadsB) {
        $null = New-Item -ItemType Directory -Force -Path $d
    }

    # fake tailscale for the PowerShell side
    $fakePs = Join-Path $script:Root 'fake-tailscale.ps1'
    Set-Content -LiteralPath $fakePs -Value @'
$drop = $env:FAKE_TS_DROP
switch ($args[1]) {
    'cp' {
        if ($env:FAKE_TS_FAIL -eq '1') { exit 1 }
        $dest = Join-Path $drop ([string]$args[3]).TrimEnd(':')
        $null = New-Item -ItemType Directory -Force -Path $dest
        Copy-Item -LiteralPath $args[2] -Destination $dest
        exit 0
    }
    'get' {
        $src = Join-Path $drop $env:FAKE_TS_SELF
        if (Test-Path $src) { Get-ChildItem -LiteralPath $src -File | Move-Item -Destination $args[-1] }
        exit 0
    }
}
exit 2
'@
    # fake tailscale for the bash side
    $fakeSh = Join-Path $script:Root 'fake-tailscale.sh'
    [IO.File]::WriteAllText($fakeSh, @'
#!/usr/bin/env bash
drop="$(cygpath -u "$FAKE_TS_DROP")"
case "$2" in
  cp)
    [ "${FAKE_TS_FAIL:-}" = 1 ] && exit 1
    mkdir -p "$drop/${4%:}" && cp "$(cygpath -u "$3")" "$drop/${4%:}/" ;;
  get)
    dest="$(cygpath -u "${@: -1}")"
    for f in "$drop/$FAKE_TS_SELF"/*; do [ -f "$f" ] && mv "$f" "$dest/"; done
    exit 0 ;;
  *) exit 2 ;;
esac
'@.Replace("`r`n", "`n"))
    $env:FAKE_TS_DROP = $script:Drop
    $env:DOTFILES_SYNC_NO_NOTIFY = '1'
    $env:FAKE_TS_FAIL = ''

    $syncignore = "# never crosses`nwork-only/`n/anchored-only.txt`n!not-a-real-negation.txt`n"
    $blob = [byte[]](0..255 + 0..255)
    foreach ($repo in $script:RepoA, $script:RepoB) {
        $null = Invoke-TestGit $repo init -q -b main
        $null = Invoke-TestGit $repo config user.name 'Test User'
        Set-RepoFile $repo '.syncignore' $syncignore
        Set-RepoFile $repo 'shared.txt' "line 1`nline 2`nline 3`n"
        Set-RepoFile $repo 'conflict.txt' "original`n"
        Set-RepoFile $repo 'to-delete.txt' "bye`n"
        Set-RepoFile $repo 'to-rename.txt' "moving`n"
        Set-RepoFile $repo 'bin/data.bin' $blob
        Set-RepoFile $repo 'anchored-only.txt' "local to $(Split-Path -Leaf $repo)`n"
    }
    $null = Invoke-TestGit $script:RepoA config user.email 'me@personal.example'
    $null = Invoke-TestGit $script:RepoA config core.autocrlf false   # like the Mac
    $null = Invoke-TestGit $script:RepoB config user.email 'me@work.example'
    Set-RepoFile $script:RepoA 'work-only/a.txt' "personal side`n"
    Set-RepoFile $script:RepoB 'work-only/a.txt' "work side`n"
    foreach ($repo in $script:RepoA, $script:RepoB) {
        $null = Invoke-TestGit $repo add -A
        $null = Invoke-TestGit $repo commit -q -m 'initial'
    }

    $env:DOTFILES_SYNC_TAILSCALE = $fakePs
    $r = Invoke-B setup --label work --peer a --email '@work\.example$'
    Assert-That ($r.Code -eq 0) 'setup (PowerShell) succeeds' $r.Out
    $env:DOTFILES_SYNC_TAILSCALE = ConvertTo-PosixPath $fakeSh
    $r = Invoke-A setup --label personal --peer b
    Assert-That ($r.Code -eq 0) 'setup (bash) succeeds' $r.Out
}

<#
.SYNOPSIS
    Runs an 'auto' cycle on B (PowerShell) with its fake tailscale.
#>
function Invoke-AutoB {
    $env:DOTFILES_SYNC_TAILSCALE = Join-Path $script:Root 'fake-tailscale.ps1'
    return (Invoke-B auto)
}

<#
.SYNOPSIS
    Runs an 'auto' cycle on A (bash) with its fake tailscale.
#>
function Invoke-AutoA {
    $env:DOTFILES_SYNC_TAILSCALE = ConvertTo-PosixPath (Join-Path $script:Root 'fake-tailscale.sh')
    return (Invoke-A auto)
}

<#
.SYNOPSIS
    Returns the content of a state file of a test repo, or ''.
.PARAMETER Repo
    Repo path.
.PARAMETER Name
    File under .git/dotfiles-sync.
#>
function Get-StateText {
    param([string]$Repo, [string]$Name)
    $p = Join-Path $Repo ".git\dotfiles-sync\$Name"
    if (Test-Path -LiteralPath $p) { return [IO.File]::ReadAllText($p) }
    return ''
}

# --- tests ----------------------------------------------------------------------

if (-not $script:Bash) { throw 'Git for Windows bash.exe not found' }
Write-Host "test bed: $($script:Root)"
try {
    Write-Host "`n[setup]"
    Initialize-TestBed
    Assert-That ((Compare-Repos) -eq '') 'repos start identical' (Compare-Repos)

    Write-Host "`n[PowerShell -> bash: edits, binary, CRLF, UTF-8, delete, rename, ignored paths]"
    Set-RepoFile $script:RepoB 'shared.txt' "line 1`nline 2 (work)`nline 3`n"
    Set-RepoFile $script:RepoB 'bin/new.bin' ([byte[]](255..0 + 0, 0, 0, 7))
    Set-RepoFile $script:RepoB 'crlf.txt' "one`r`ntwo`r`n"
    Set-RepoFile $script:RepoB 'unicode/héllo.txt' "ünïcödé ✓`n"
    Remove-Item (Join-Path $script:RepoB 'to-delete.txt')
    Move-Item (Join-Path $script:RepoB 'to-rename.txt') (Join-Path $script:RepoB 'renamed.txt')
    Set-RepoFile $script:RepoB 'work-only/a.txt' "work side, changed`n"
    Set-RepoFile $script:RepoB 'anchored-only.txt' "work change that must stay here`n"
    $r = Invoke-AutoB
    Assert-That ($r.Code -eq 0) 'auto on B succeeds' $r.Out
    Assert-That (@(Get-Dropped 'a').Count -eq 1) 'B sent one patch to A' $r.Out
    $patchText = [IO.File]::ReadAllText(@(Get-Dropped 'a')[0].FullName)
    Assert-That ($patchText.StartsWith("# dotfiles-sync patch v1`n# from: work`n")) 'patch header is LF-only, no BOM'
    Assert-That (-not $patchText.Contains('work-only/')) 'ignored directory is not in the patch'
    Assert-That (-not $patchText.Contains('anchored-only.txt')) 'anchored ignored file is not in the patch'
    $r = Invoke-AutoA
    Assert-That ($r.Code -eq 0) 'auto on A succeeds' $r.Out
    Assert-That ((Compare-Repos) -eq '') 'A matches B after the sync' ((Compare-Repos) + "`n" + $r.Out)
    $trailer = Invoke-TestGit $script:RepoA log -1 '--format=%(trailers:key=Dotfiles-Sync-Source,valueonly)'
    Assert-That ([string]$trailer -match '^work [0-9a-f]{40}') 'imported commit carries the source trailer' ([string]$trailer)
    Assert-That ((Get-Content (Join-Path $script:RepoA 'work-only/a.txt') -Raw) -eq "personal side`n") "A's ignored file is untouched"
    Assert-That ((Get-Content (Join-Path $script:RepoA 'anchored-only.txt') -Raw) -eq "local to a`n") "A's anchored ignored file is untouched"

    Write-Host "`n[echo suppression]"
    $r = Invoke-AutoA
    Assert-That (@(Get-Dropped 'b').Count -eq 0) 'A sends nothing back after importing' $r.Out
    $r = Invoke-AutoB
    Assert-That (@(Get-Dropped 'a').Count -eq 0) 'B has nothing new to send' $r.Out

    Write-Host "`n[bash -> PowerShell, UTF-8 subject, CRLF blob]"
    [IO.File]::WriteAllText((Join-Path $script:RepoA 'mac-crlf.txt'), "x`r`ny`r`n")
    Set-RepoFile $script:RepoA 'shared.txt' "line 1`nline 2 (work)`nline 3`nline 4 (personal)`n"
    $null = Invoke-TestGit $script:RepoA add -A
    $null = Invoke-TestGit $script:RepoA commit -q -m 'ünïcode subject ✓'
    $r = Invoke-AutoA
    Assert-That (@(Get-Dropped 'b').Count -eq 1) 'A sent one patch to B' $r.Out
    $r = Invoke-AutoB
    Assert-That ($r.Code -eq 0) 'auto on B imports it' $r.Out
    Assert-That ((Compare-Repos) -eq '') 'B matches A after the sync' ((Compare-Repos) + "`n" + $r.Out)
    $subject = [string](Invoke-TestGit $script:RepoB log -1 '--format=%s')
    Assert-That ($subject -eq 'sync(personal): ünïcode subject ✓') 'UTF-8 subject survives the trip' $subject

    Write-Host "`n[duplicate patch is a no-op]"
    $done = Get-ChildItem (Join-Path $script:RepoB '.git\dotfiles-sync\inbox\done') -File | Sort-Object Name | Select-Object -Last 1
    $before = [string](Invoke-TestGit $script:RepoB rev-parse HEAD)
    $r = Invoke-B import $done.FullName
    $after = [string](Invoke-TestGit $script:RepoB rev-parse HEAD)
    Assert-That ($r.Code -eq 0 -and $before -eq $after) 're-importing a patch changes nothing' $r.Out

    Write-Host "`n[secret scan blocks sending, output masked]"
    $token = 'ghp_' + ('Ab1' * 12)
    Set-RepoFile $script:RepoB 'leak.txt' "token=$token`n"
    $r = Invoke-AutoB
    Assert-That (@(Get-Dropped 'a').Count -eq 0) 'nothing is sent while a secret is in the changes' $r.Out
    Assert-That (-not $r.Out.Contains($token)) 'the secret is not printed' $r.Out
    Assert-That ((Get-StateText $script:RepoB 'last-run') -match ' blocked ') 'last-run says blocked' (Get-StateText $script:RepoB 'last-run')
    Add-Content -LiteralPath (Join-Path $script:RepoB '.syncignore') -Value 'leak.txt' -NoNewline:$false
    $r = Invoke-AutoB
    Assert-That ((Get-StateText $script:RepoB 'last-run') -match ' ok') 'listing the file in .syncignore unblocks sync' ($r.Out + (Get-StateText $script:RepoB 'last-run'))
    Get-Dropped 'a' | Remove-Item

    Write-Host "`n[failed send stays queued and is retried]"
    Set-RepoFile $script:RepoB 'queued.txt' "queued`n"
    $env:FAKE_TS_FAIL = '1'
    $r = Invoke-AutoB
    $env:FAKE_TS_FAIL = ''
    $queued = @(Get-ChildItem (Join-Path $script:RepoB '.git\dotfiles-sync\outbox') -File -Filter 'dotfiles-sync-*')
    Assert-That ($queued.Count -eq 1 -and @(Get-Dropped 'a').Count -eq 0) 'patch stays queued when Taildrop fails' $r.Out
    $r = Invoke-AutoB
    Assert-That (@(Get-Dropped 'a').Count -eq 1) 'next cycle sends the queued patch' $r.Out
    $r = Invoke-AutoA
    Assert-That ((Compare-Repos) -eq '') 'A applies it' ((Compare-Repos) + "`n" + $r.Out)

    Write-Host "`n[conflict is held, later patches wait, tree stays clean]"
    Set-RepoFile $script:RepoA 'conflict.txt' "personal version`n"
    Set-RepoFile $script:RepoB 'conflict.txt' "work version`n"
    $r = Invoke-AutoA                      # A sends its version
    $r = Invoke-AutoB                      # B commits its own, then A's patch conflicts
    Assert-That ($r.Code -eq 0) 'auto on B completes' $r.Out
    Assert-That ((Get-StateText $script:RepoB 'last-run') -match ' held ') 'last-run says held' ((Get-StateText $script:RepoB 'last-run') + $r.Out)
    Assert-That (@(Get-ChildItem (Join-Path $script:RepoB '.git\dotfiles-sync\inbox\held') -File).Count -eq 1) 'patch moved to inbox/held'
    Assert-That (-not (Invoke-TestGit $script:RepoB status --porcelain)) "B's tree is clean after the failed apply"
    Assert-That ((Get-Content (Join-Path $script:RepoB 'conflict.txt') -Raw) -eq "work version`n") "B keeps its own version"
    Set-RepoFile $script:RepoA 'after-conflict.txt' "later`n"
    $r = Invoke-AutoA
    $r = Invoke-AutoB
    Assert-That (-not (Test-Path (Join-Path $script:RepoB 'after-conflict.txt'))) 'later patches wait behind the held one' $r.Out
    # B's own conflicting change went to A: A holds it too
    Assert-That (@(Get-ChildItem (Join-Path $script:RepoA '.git\dotfiles-sync\inbox\held') -File).Count -eq 1) 'A holds the conflicting change from B' (Invoke-A status).Out

    Write-Host "`n[clearing holds: skip the conflicting change, apply the rest]"
    # B, interactively: "n" skips the held conflicting change, "y" applies the queued one
    $env:FAKE_TS_SELF = 'b'
    $env:DOTFILES_SYNC_DOWNLOADS = $script:DownloadsB
    $out = "n`ny`n" | & pwsh -NoProfile -File $script:Ps1 -C $script:RepoB import 2>&1 | Out-String
    Assert-That ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $script:RepoB 'after-conflict.txt'))) 'interactive import on B works through held + queued patches' $out
    Assert-That (@(Get-ChildItem (Join-Path $script:RepoB '.git\dotfiles-sync\inbox\held') -File).Count -eq 0) "B's hold is cleared" $out
    $out = '' | & pwsh -NoProfile -File $script:Ps1 -C $script:RepoB import (Get-ChildItem (Join-Path $script:RepoB '.git\dotfiles-sync\inbox\done') -File | Select-Object -First 1).FullName 2>&1 | Out-String
    Assert-That ($LASTEXITCODE -eq 0) 'import with closed input does not loop (nothing left to ask)' $out
    # A: record the conflicting change as skipped (what answering "n" does), then apply the held file
    $heldA = Get-ChildItem (Join-Path $script:RepoA '.git\dotfiles-sync\inbox\held') -File | Select-Object -First 1
    $sha = (Select-String -LiteralPath $heldA.FullName -Pattern '^=== change ([0-9a-f]+) ===$' | Select-Object -First 1).Matches[0].Groups[1].Value
    Add-Content -LiteralPath (Join-Path $script:RepoA '.git\dotfiles-sync\skipped') -Value "work $sha"
    $r = Invoke-A import --auto ($heldA.FullName -replace '\\', '/')
    Assert-That ($r.Code -eq 0 -and @(Get-ChildItem (Join-Path $script:RepoA '.git\dotfiles-sync\inbox\held') -File).Count -eq 0) "A's hold is cleared" $r.Out
    # settle conflict.txt by hand, the way you would
    Set-RepoFile $script:RepoA 'conflict.txt' "work version`n"
    $r = Invoke-AutoA; $r = Invoke-AutoB; $r = Invoke-AutoA
    Assert-That ((Compare-Repos) -eq '') 'repos converge again' ((Compare-Repos) + "`n" + $r.Out)

    Write-Host "`n[baseline recovery after a rebase rewrote last-export]"
    Set-RepoFile $script:RepoB 'rebase-1.txt' "one`n"
    $r = Invoke-AutoB                      # exports; last-export = this commit
    $r = Invoke-AutoA
    $null = Invoke-TestGit $script:RepoB commit -q --amend -m 'amended (rewrites last-export)'
    Set-RepoFile $script:RepoB 'rebase-2.txt' "two`n"
    $r = Invoke-AutoB
    Assert-That ($r.Code -eq 0 -and $r.Out -match 'no longer on this branch') 'export falls back to the merge base' $r.Out
    $r = Invoke-AutoA
    Assert-That ($r.Code -eq 0) 'A takes the re-sent and the new change' $r.Out
    Assert-That ((Compare-Repos) -eq '') 'repos still match' ((Compare-Repos) + "`n" + $r.Out)

    Write-Host "`n[locking]"
    $lockPath = Join-Path $script:RepoB '.git\dotfiles-sync\lock'
    $held = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    try { $r = Invoke-AutoB } finally { $held.Dispose() }
    Assert-That ($r.Code -eq 0 -and $r.Out -match 'holds the lock; skipping') 'PowerShell auto skips while the lock is held' $r.Out
    $bg = Start-Process -FilePath $script:Bash -ArgumentList @($script:Sh, '-C', ($script:RepoA -replace '\\', '/'), 'with-lock', 'sleep', '6') -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 2
    $r = Invoke-AutoA
    $bg.WaitForExit()
    Assert-That ($r.Code -eq 0 -and $r.Out -match 'holds the lock; skipping') 'bash auto skips while with-lock runs' $r.Out

    # one clone used by both implementations (Windows + WSL, like ~/dotfiles here)
    $held = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    try { $out = '' | & $script:Bash $script:Sh -C ($script:RepoB -replace '\\', '/') auto 2>&1 | Out-String }
    finally { $held.Dispose() }
    Assert-That ($out -match 'holds the lock; skipping') 'bash honours the Windows lock on a shared clone' $out
    $bashLock = Join-Path $script:RepoB '.git\dotfiles-sync\lock.d'
    $null = New-Item -ItemType Directory -Path $bashLock
    Set-Content -LiteralPath (Join-Path $bashLock 'pid') -Value '99999'
    try { $r = Invoke-AutoB } finally { Remove-Item -LiteralPath $bashLock -Recurse -Force }
    Assert-That ($r.Code -eq 0 -and $r.Out -match 'holds the lock; skipping') 'PowerShell honours the bash lock on a shared clone' $r.Out
    $null = New-Item -ItemType Directory -Path $bashLock
    Set-Content -LiteralPath (Join-Path $bashLock 'pid') -Value '99999'
    (Get-Item -LiteralPath $bashLock).LastWriteTime = (Get-Date).AddHours(-1)
    $r = Invoke-AutoB
    Assert-That ($r.Code -eq 0 -and $r.Out -notmatch 'holds the lock' -and -not (Test-Path $bashLock)) 'a bash lock left behind for 30+ minutes is taken over' $r.Out

    Write-Host "`n[snapshots: never auto-applied; .syncignore incl. /anchored respected]"
    Set-RepoFile $script:RepoB 'anchored-only.txt' "work copy - must not reach A`n"
    Set-RepoFile $script:RepoB 'snap-only.txt' "from snapshot`n"
    $null = Invoke-TestGit $script:RepoB add -A
    $null = Invoke-TestGit $script:RepoB commit -q -m 'snapshot content'
    $r = Invoke-B snapshot --no-send --yes
    $snap = Get-ChildItem (Join-Path $script:RepoB '.git\dotfiles-sync\outbox\manual') -Filter '*.snapshot.tar' | Select-Object -First 1
    Assert-That ($null -ne $snap) 'PowerShell snapshot written' $r.Out
    Copy-Item $snap.FullName $script:DownloadsA
    $r = Invoke-AutoA
    Assert-That ((Get-StateText $script:RepoA 'last-run') -match ' held ') 'auto holds an incoming snapshot' ((Get-StateText $script:RepoA 'last-run') + $r.Out)
    $heldSnap = Get-ChildItem (Join-Path $script:RepoA '.git\dotfiles-sync\inbox\held') -Filter '*.snapshot.tar' | Select-Object -First 1
    $r = Invoke-A import ($heldSnap.FullName -replace '\\', '/')
    Assert-That ((Get-Content (Join-Path $script:RepoA 'snap-only.txt') -Raw) -eq "from snapshot`n") 'bash import lays the snapshot over the tree' $r.Out
    Assert-That ((Get-Content (Join-Path $script:RepoA 'anchored-only.txt') -Raw) -eq "local to a`n") '/anchored pattern keeps the local file' $r.Out
    $null = Invoke-TestGit $script:RepoA checkout -q -- .
    $null = Invoke-TestGit $script:RepoA clean -fdq
    Assert-That (-not (Test-Path -LiteralPath $heldSnap.FullName)) "the imported snapshot leaves inbox/held"

    $r = Invoke-A snapshot --no-send --yes
    $snapA = Get-ChildItem (Join-Path $script:RepoA '.git\dotfiles-sync\outbox\manual') -Filter '*.snapshot.tar' | Select-Object -First 1
    Assert-That ($null -ne $snapA) 'bash snapshot written' $r.Out
    $r = Invoke-B import $snapA.FullName
    Assert-That ($r.Code -eq 0 -and (Get-Content (Join-Path $script:RepoB 'anchored-only.txt') -Raw) -eq "work copy - must not reach A`n") 'PowerShell import keeps the /anchored local file' $r.Out
    Assert-That ((Get-Content (Join-Path $script:RepoB 'work-only/a.txt') -Raw) -eq "work side, changed`n") 'PowerShell import keeps ignored directories' $r.Out
    $null = Invoke-TestGit $script:RepoB checkout -q -- .
    $null = Invoke-TestGit $script:RepoB clean -fdq

    Write-Host "`n[pre-push identity check]"
    $null = Invoke-TestGit $script:RepoB -c user.email=someone@else.example commit -q --allow-empty -m 'wrong identity'
    $sha = [string](Invoke-TestGit $script:RepoB rev-parse HEAD)
    $line = "refs/heads/main $sha refs/heads/main $('0' * 40)"
    $out = $line | & pwsh -NoProfile -NonInteractive -File $script:Ps1 -C $script:RepoB check-push origin 2>&1 | Out-String
    Assert-That ($LASTEXITCODE -eq 1 -and $out -match 'push refused') 'check-push refuses a foreign identity' $out
    $hook = Get-Content (Join-Path $script:RepoB '.git\hooks\pre-push') -Raw
    Assert-That ($hook -match 'pwsh .*dotfiles-sync\.ps1.*check-push') 'setup installed the PowerShell pre-push hook' $hook
}
catch {
    $script:Failures++
    Write-Host "  ERROR $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
}
finally {
    Remove-Item Env:FAKE_TS_SELF, Env:FAKE_TS_DROP, Env:FAKE_TS_FAIL, Env:DOTFILES_SYNC_DOWNLOADS, Env:DOTFILES_SYNC_TAILSCALE, Env:DOTFILES_SYNC_NO_NOTIFY -ErrorAction SilentlyContinue
    if ($Keep -or $script:Failures -gt 0) { Write-Host "`ntest bed kept at $($script:Root)" }
    else { Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n$($script:Passes) passed, $($script:Failures) failed"
exit ([int]($script:Failures -gt 0))
