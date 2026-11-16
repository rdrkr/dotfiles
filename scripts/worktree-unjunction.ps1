#Requires -Version 5.1
<#
.SYNOPSIS
    Replaces the submodule junctions in chosen worktrees with empty folders, so the worktrees can be deleted.
.DESCRIPTION
    Lists the linked worktrees of a repository in a console checkbox picker. For each one ticked,
    every submodule path from that worktree's own .gitmodules that is a junction is deleted (the
    link only, never its target) and recreated as an empty directory.
.PARAMETER Repo
    Name of the main checkout under $env:USERPROFILE\development\repos, e.g. mgnt.magnet.
.EXAMPLE
    worktree-unjunction.ps1 mgnt.magnet
#>
param(
    [Parameter(Mandatory)][string]$Repo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Shows a console checkbox list and returns the indices of the ticked items.
.DESCRIPTION
    Keys: Up/Down move, Space toggles, A toggles all, Enter applies, Esc cancels.
    The first row, "(all)", ticks or clears every item.
.PARAMETER Items
    The labels to choose from.
.PARAMETER Title
    The heading printed above the list.
.OUTPUTS
    System.Int32. One zero-based index into Items per ticked item; nothing when cancelled.
#>
function Select-Checkbox {
    param(
        [Parameter(Mandatory)][string[]]$Items,
        [string]$Title = 'Select'
    )
    $rows = @('(all)') + $Items
    $checked = New-Object bool[] $rows.Count
    $pos = 0
    Write-Host $Title
    Write-Host 'Up/Down move   Space toggle   A all   Enter apply   Esc cancel' -ForegroundColor DarkGray
    for ($i = 0; $i -lt $rows.Count; $i++) { Write-Host '' }
    $top = [Console]::CursorTop - $rows.Count
    $width = [Console]::BufferWidth - 1
    $cursorWas = [Console]::CursorVisible
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            for ($i = 0; $i -lt $rows.Count; $i++) {
                [Console]::SetCursorPosition(0, $top + $i)
                $marker = if ($i -eq $pos) { '>' } else { ' ' }
                $box = if ($checked[$i]) { '[x]' } else { '[ ]' }
                $line = "$marker $box $($rows[$i])"
                if ($line.Length -gt $width) { $line = $line.Substring(0, $width) }
                $style = if ($i -eq $pos) { @{ ForegroundColor = 'Cyan' } } else { @{} }
                Write-Host $line.PadRight($width) -NoNewline @style
            }
            $key = [Console]::ReadKey($true).Key
            if ($key -eq 'UpArrow') { $pos = ($pos - 1 + $rows.Count) % $rows.Count }
            elseif ($key -eq 'DownArrow') { $pos = ($pos + 1) % $rows.Count }
            elseif ($key -eq 'Spacebar' -or $key -eq 'A') {
                if ($pos -eq 0 -or $key -eq 'A') {
                    $value = -not $checked[0]
                    for ($i = 0; $i -lt $rows.Count; $i++) { $checked[$i] = $value }
                } else {
                    $checked[$pos] = -not $checked[$pos]
                    $checked[0] = -not ($checked[1..($rows.Count - 1)] -contains $false)
                }
            }
            elseif ($key -eq 'Enter') {
                for ($i = 1; $i -lt $rows.Count; $i++) { if ($checked[$i]) { $i - 1 } }
                return
            }
            elseif ($key -eq 'Escape') { return }
        }
    } finally {
        [Console]::CursorVisible = $cursorWas
        [Console]::SetCursorPosition(0, $top + $rows.Count)
    }
}

$main = Join-Path $env:USERPROFILE "development\repos\$Repo"
if (-not (Test-Path -LiteralPath $main)) { throw "No repository at $main" }
$main = (Resolve-Path -LiteralPath $main).Path.TrimEnd('\')

$wts = @()
$cur = $null
foreach ($l in (git -C $main worktree list --porcelain)) {
    if ($l -like 'worktree *') {
        $cur = [pscustomobject]@{ Path = ($l.Substring(9) -replace '/', '\'); Branch = '(detached)' }
        if ($cur.Path -ne $main) { $wts += $cur }
    } elseif ($l -like 'branch refs/heads/*') {
        $cur.Branch = $l.Substring(18)
    }
}
if ($wts.Count -eq 0) { Write-Host "No linked worktrees under $main."; return }

$labels = @($wts | ForEach-Object { "$($_.Branch)  ->  $($_.Path)" })
$chosen = @(Select-Checkbox -Items $labels -Title "Worktrees of $main")
if ($chosen.Count -eq 0) { Write-Host 'Nothing selected.'; return }

foreach ($idx in $chosen) {
    $wt = $wts[$idx].Path
    $gm = Join-Path $wt '.gitmodules'
    if (-not (Test-Path -LiteralPath $gm)) { Write-Host "skipped $wt (no .gitmodules)"; continue }
    $paths = git -C $wt config -f $gm --get-regexp '\.path$' | ForEach-Object { ($_ -split ' ', 2)[1] }
    foreach ($p in $paths) {
        $full = Join-Path $wt ($p -replace '/', '\')
        if ((Test-Path -LiteralPath $full) -and (Get-Item -LiteralPath $full -Force).LinkType -eq 'Junction') {
            [IO.Directory]::Delete($full, $false)
            [void][IO.Directory]::CreateDirectory($full)
            "removed $full"
        }
    }
}
