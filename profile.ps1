# profile.ps1 - PowerShell equivalent of .zshrc

# initialization
$env:XDG_CONFIG_HOME = "$env:USERPROFILE\.config"

# platform detection
if ($null -ne $IsWindows -and $IsWindows) {
    $global:_OS = "windows"
} elseif ($null -ne $IsMacOS -and $IsMacOS) {
    $global:_OS = "macos"
} elseif ($null -ne $IsLinux -and $IsLinux) {
    $global:_OS = "linux"
} elseif ($PSVersionTable.PSVersion.Major -le 5) {
    $global:_OS = "windows"
} else {
    $global:_OS = "unknown"
}

# load .env
$envFile = "$env:USERPROFILE\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match '^\s*([^#][^=]+)=(.*)$' } | ForEach-Object {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim() -replace '^["'']|["'']$', ''
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

# starship
$env:STARSHIP_CONFIG = "$env:USERPROFILE\.config\starship\starship.toml"
if (Test-Path $env:STARSHIP_CONFIG) {
    $configContent = Get-Content $env:STARSHIP_CONFIG -Raw
    if ($configContent -notmatch '\[.*\]' -and $configContent.Length -lt 256) {
        $resolved = Join-Path (Split-Path $env:STARSHIP_CONFIG) $configContent.Trim()
        if (Test-Path $resolved) {
            $env:STARSHIP_CONFIG = $resolved
        }
    }
}
# fzf
$env:FZF_DEFAULT_OPTS = '--color=bg:#282828,bg+:#3c3836 --color=fg:#ebdbb2,fg+:#fbf1c7 --color=hl:#83a598,hl+:#8ec07c --color=info:#fabd2f,prompt:#fabd2f,pointer:#fe8019 --color=marker:#b8bb26,spinner:#8ec07c,header:#83a598 --layout=reverse-list'

# editor
$env:EDITOR = "nvim"
$env:VISUAL = $env:EDITOR

# paths
$pathDirs = @(
    "$env:USERPROFILE\.local\bin",
    "$env:USERPROFILE\local\bin",
    "$env:USERPROFILE\.npm-global\bin",
    "$env:USERPROFILE\.antigravity\antigravity\bin",
    "$env:USERPROFILE\.bun\bin"
)

$currentPaths = $env:PATH -split ';'
foreach ($p in $pathDirs) {
    if (-not ($currentPaths -contains $p)) {
        $env:PATH = "$p;$env:PATH"
    }
}

# psmux
# The PowerShell counterpart of the tmux block in .zshrc: docker-style random
# session names, auto-attach to a detached session on a new terminal, and the
# working directory carried back out to the parent shell on exit.

## generate fun docker-style names
function Get-PsmuxRandomName {
    <#
    .SYNOPSIS
        Returns an unused "<adjective>-<animal>" psmux session name.
    .DESCRIPTION
        The PowerShell twin of _tmux_random_name in .zshrc. The word lists are
        deliberately identical so sessions are named from the same pool whether
        they were started from zsh under WSL or from pwsh on Windows. Retries
        until has-session reports the candidate free.
    .OUTPUTS
        System.String. A session name not currently in use.
    #>
    $adjectives = @('brave', 'calm', 'clever', 'cool', 'daring', 'eager', 'fancy', 'gentle', 'happy', 'jolly', 'angry')
    $animals    = @('otter', 'fox', 'panda', 'koala', 'falcon', 'badger', 'lynx', 'wolf', 'raven', 'hawk', 'hamster')

    while ($true) {
        $name = "$(Get-Random -InputObject $adjectives)-$(Get-Random -InputObject $animals)"
        & psmux has-session -t $name 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return $name }
    }
}

function Get-PsmuxDetachedSession {
    <#
    .SYNOPSIS
        Lists the psmux sessions that currently have no client attached.
    .DESCRIPTION
        .zshrc lets tmux do the filtering server-side with `list-sessions -f`.
        psmux accepts that flag but ignores it and returns nothing, so the same
        predicate is applied here against `ls -F` output instead.
    .OUTPUTS
        System.String. Zero or more session names, oldest first, written to the
        pipeline one at a time.
    .NOTES
        Names are emitted individually rather than returned as an array on
        purpose. PowerShell unrolls a one-element array on the way out of a
        function, so `return @($name)` hands back a bare string whose [0] is its
        first character - but the usual `return ,@(...)` guard against that then
        double-wraps once the caller adds its own @(). Emitting plainly and
        letting the caller wrap exactly once is the only shape that behaves for
        zero, one, and many sessions alike.
    #>
    $rows = & psmux ls -F '#{session_name}|#{session_attached}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $rows) { return }

    $rows |
        Where-Object { $_ -match '\|0\s*$' } |
        ForEach-Object { ($_ -split '\|')[0] }
}

function Get-PsmuxPwdFile {
    <#
    .SYNOPSIS
        Returns the path of the file a psmux session records its cwd in.
    .DESCRIPTION
        .zshrc hands tmux a mktemp path through `new-session -e TMUX_PWD_FILE`.
        psmux has no -e, so the path is derived from the session name on both
        sides instead: the shell inside the session knows the name from
        PSMUX_SESSION, and the shell that launched it knows what it attached to.
    .PARAMETER Session
        The psmux session name.
    .OUTPUTS
        System.String. Full path to the session's cwd file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Session
    )

    Join-Path ([System.IO.Path]::GetTempPath()) "psmux-pwd-$Session.txt"
}

function Start-PsmuxStatsDaemon {
    <#
    .SYNOPSIS
        Ensures this pane's psmux server has a CPU/RAM poller running.
    .DESCRIPTION
        The psmux-cpu plugin polls by hanging `run-shell "pwsh -File
        system_stats.ps1"` off the status-interval hook, which makes the psmux
        *server* start a process on every status-bar tick. A server spawned into
        the background has no console, so CreateProcess refuses to inherit its
        standard handles and every tick fails with

            run-shell: pwsh -NoProfile -File "...\system_stats.ps1":
            The handle is invalid. (os error 6)

        - a repeating error on the message line and a status bar frozen at
        whatever the last successful poll returned. ~/.psmux.conf unsets those
        hooks; this starts the replacement.

        It has to be launched from here rather than from ~/.psmux.conf: a
        run-shell in the config is still a server spawn, so it would fail on the
        very servers that need it. A pane shell is an ordinary process with a
        console and spawns fine.

        The daemon holds a mutex named for its server's pid for as long as it
        runs, so the check below is an in-process handle open - no spawn - and
        only the first pane of a server actually starts anything.
    .EXAMPLE
        Start-PsmuxStatsDaemon
    #>
    if ($env:TMUX -notmatch 'psmux-(\d+)') { return }
    $serverPid = $Matches[1]

    $mutexName = "Local\psmux-stats-daemon-$serverPid"
    $existing  = $null
    if ([System.Threading.Mutex]::TryOpenExisting($mutexName, [ref]$existing)) {
        $existing.Dispose()
        return
    }

    $daemon = Join-Path $env:USERPROFILE 'dotfiles\scripts\psmux-stats-daemon.ps1'
    if (-not (Test-Path -LiteralPath $daemon)) { return }

    Start-Process -FilePath 'pwsh' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile'
        '-NonInteractive'
        '-File', $daemon
        '-Worker'
        '-ServerPid', $serverPid
    )
}

function Start-PsmuxAutosave {
    <#
    .SYNOPSIS
        Ensures the periodic psmux-resurrect save loop is running.
    .DESCRIPTION
        The psmux counterpart of tmux-continuum's periodic save; see
        scripts/psmux-autosave.ps1 for why it is started from a pane shell
        rather than from ~/.psmux.conf. The loop holds a machine-wide mutex, so
        the check below is an in-process handle open - no spawn - and only a
        pane with no loop running starts one.
    .EXAMPLE
        Start-PsmuxAutosave
    #>
    $existing = $null
    if ([System.Threading.Mutex]::TryOpenExisting('Local\psmux-autosave', [ref]$existing)) {
        $existing.Dispose()
        return
    }

    $autosave = Join-Path $env:USERPROFILE 'dotfiles\scripts\psmux-autosave.ps1'
    if (-not (Test-Path -LiteralPath $autosave)) { return }

    Start-Process -FilePath 'pwsh' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile'
        '-NonInteractive'
        '-File', $autosave
        '-Worker'
    )
}

function Restore-PsmuxAfterBoot {
    <#
    .SYNOPSIS
        Brings back, once per boot, the psmux sessions psmux-resurrect saved
        last, before a new tab picks a session to attach to.
    .DESCRIPTION
        The counterpart of _tmux_restore_after_boot in .zshrc. Acts only on the
        first call after a reboot, and only when psmux has no sessions yet, so
        sessions closed during a boot are not brought back by the next tab.
        The restore runs in a child process: restore.ps1 sets environment
        variables and calls `exit`, and neither should reach this shell (or the
        psmux server it is about to start).
    .EXAMPLE
        Restore-PsmuxAfterBoot
    #>
    # boot time in epoch seconds; recomputed values jitter by a few ms, so two
    # values within a couple of minutes are the same boot
    try {
        $uptimeMs = [Environment]::TickCount64
    } catch {
        $uptimeMs = ((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMilliseconds
    }
    $bootTime = [long]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [math]::Floor($uptimeMs / 1000))

    $marker   = Join-Path $env:USERPROFILE '.psmux\restored-boot'
    $restored = [long]0
    if (Test-Path -LiteralPath $marker) {
        [void][long]::TryParse((Get-Content -LiteralPath $marker -Raw).Trim(), [ref]$restored)
    }
    if ([math]::Abs($bootTime - $restored) -le 120) { return }

    # record the boot first, so a failed restore is not retried in every tab
    New-Item -ItemType Directory -Path (Split-Path $marker) -Force | Out-Null
    Set-Content -LiteralPath $marker -Value $bootTime

    # sessions already running: nothing was lost
    $running = & psmux ls 2>$null
    if ($LASTEXITCODE -eq 0 -and $running) { return }

    $restore = Join-Path $env:USERPROFILE '.psmux\plugins\psmux-resurrect\scripts\restore.ps1'
    $last    = Join-Path $env:USERPROFILE '.psmux\resurrect\last'
    if (-not (Test-Path -LiteralPath $restore) -or -not (Test-Path -LiteralPath $last)) { return }

    Write-Host 'psmux: restoring saved sessions...'
    & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $restore *> $null
}

## auto-start psmux when opening a new Windows Terminal tab, mirroring the WSL
## auto-launch block in .zshrc. Skipped inside an existing session (psmux sets
## TMUX in its panes), outside Windows Terminal, and in non-interactive hosts.
##
## This runs before starship and the shell integrations are initialised: the
## shell that starts psmux only waits for it, so initialising all of that first
## made every new tab pay the profile's startup cost twice (once here, once in
## the pane). If this shell carries on after psmux exits, the rest loads then.
if ($env:WT_SESSION -and
    -not $env:TMUX -and
    $Host.Name -eq 'ConsoleHost' -and
    (Get-Command psmux -ErrorAction SilentlyContinue)) {

    # the psmux server inherits this shell's environment, so give it the
    # carapace bridges the integration below sets for every other shell
    if (Get-Command carapace -ErrorAction SilentlyContinue) {
        $env:CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
    }

    try {
        try { Restore-PsmuxAfterBoot } catch { }

        $detached     = @(Get-PsmuxDetachedSession)
        $psmuxSession = ''

        if ($detached.Count -gt 0) {
            $psmuxSession = [string]$detached[0]

            # More than one session waiting: open another window to pick up the
            # next one, the same way .zshrc spawns a second Ghostty/wt window.
            # Windows Terminal has no `new-window` subcommand - a new window is
            # the global `-w -1` flag, and passing `new-window` instead makes wt
            # try to *execute* it (0x80070002, file not found).
            if ($detached.Count -gt 1) {
                Start-Process -FilePath 'wt.exe' -ArgumentList '-w', '-1', 'new-tab' -ErrorAction SilentlyContinue
            }

            & psmux attach-session -t $psmuxSession
        }

        # Either there was nothing to attach to, or the attach failed - psmux
        # can list a session that has already gone away, and refusing to open a
        # shell over that would be worse than just starting fresh.
        if (-not $psmuxSession -or $LASTEXITCODE -ne 0) {
            $psmuxSession = Get-PsmuxRandomName
            & psmux new-session -s $psmuxSession
        }

        # On exit, follow the session into whatever directory it ended up in.
        $psmuxPwdFile = Get-PsmuxPwdFile $psmuxSession
        if (Test-Path $psmuxPwdFile) {
            $psmuxLastPwd = (Get-Content -LiteralPath $psmuxPwdFile -Raw).Trim()
            if ($psmuxLastPwd -and (Test-Path $psmuxLastPwd)) { Set-Location -LiteralPath $psmuxLastPwd }
            Remove-Item -LiteralPath $psmuxPwdFile -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        # A broken auto-launch must never cost the user their shell.
        Write-Warning "psmux auto-launch skipped: $($_.Exception.Message)"
    }
}

# starship prompt
if (Get-Command starship -ErrorAction SilentlyContinue) {
    & starship init powershell | Out-String | Invoke-Expression
}

# yazi
function yazi {
    <#
    .SYNOPSIS
        Runs the yazi executable, hiding WT_SESSION from it inside psmux.
    .DESCRIPTION
        yazi reads WT_SESSION as "Windows Terminal" and sends sixel, but every
        psmux pane is hosted by the inbox conhost, which strips sixel before
        psmux sees it (psmux#431), so image previews come out blank. Without
        WT_SESSION yazi falls back to chafa and draws previews as Unicode block
        art instead. The variable is restored once yazi exits. The nvim twin of
        this lives in .config/nvim/lua/plugins/yazi.nvim.lua.
    #>
    $exe = Get-Command yazi -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $wtSession = $env:WT_SESSION
    try {
        if ($env:TMUX) { Remove-Item Env:WT_SESSION -ErrorAction SilentlyContinue }
        & $exe @args
    } finally {
        $env:WT_SESSION = $wtSession
    }
}

function y {
    <#
    .SYNOPSIS
        Runs yazi and changes to the directory it was in when it quit.
    #>
    $tmp = New-TemporaryFile
    try {
        yazi @args --cwd-file="$tmp"
        $cwd = Get-Content $tmp -Raw
        if (-not [string]::IsNullOrWhiteSpace($cwd) -and $cwd.Trim() -ne (Get-Location).Path) {
            Set-Location $cwd.Trim()
        }
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

# aliases
if (Test-Path Alias:ls) { Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue }
if (Get-Command nu -ErrorAction SilentlyContinue) {
    function l { nu -c "ls -a $($args -join ' ')" }
}

if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ls { eza --color=always @args }
} else {
    function ls { Get-ChildItem @args }
}

function vim { nvim @args }
function v { nvim @args }
function lg { lazygit @args }
<#
.SYNOPSIS
    Launches superfile (spf), passing through all arguments.
#>
function s { spf @args }
function ld { lazydocker @args }
function open { start @args }
function c { Clear-Host }

# update all: run the per-OS task list with the task runner's own tsx (installing its
# dependencies on first use); options such as --verbose or --help are passed through.
function ua {
    $runner = "$env:USERPROFILE\dotfiles\scripts\run-tasks"
    $tsx = "$runner\node_modules\tsx\dist\cli.mjs"
    # esbuild's binary is platform-specific; node_modules synced from another OS lacks it
    $esbuild = "$runner\node_modules\@esbuild\" + (node -p "process.platform + '-' + process.arch")
    if (-not (Test-Path $tsx) -or -not (Test-Path $esbuild)) {
        Write-Host "ua: installing task runner dependencies..."
        npm ci --prefix $runner --silent
        if ($LASTEXITCODE -ne 0) { return }
    }
    node $tsx "$runner\run-tasks.ts" "$runner\update-$($global:_OS).yaml" @args
}

# claude code aliases
function cc { claude --dangerously-skip-permissions @args }
function ccs { & "$env:USERPROFILE\dotfiles\scripts\ccswitch.ps1" @args }
function ccl { ccs --list }
function cc1 { ccs --switch-to 1; cc @args }
function cc2 { ccs --switch-to 2; cc @args }

# dotfiles-sync: keep this repo and the other one in sync (see scripts/dotfiles-sync.sh)
function dotfiles-sync {
    <#
    .SYNOPSIS
        Runs dotfiles-sync from PowerShell.
    .DESCRIPTION
        On Windows this is the native scripts/dotfiles-sync.ps1, run in its own
        pwsh process (it needs PowerShell 7 and exits with a status code);
        elsewhere it is scripts/dotfiles-sync.sh. The repo is
        $env:DOTFILES_SYNC_REPO when set - put it in profile.local.ps1 when the
        repo does not live at ~\dotfiles - and ~\dotfiles otherwise.
        Arguments are passed through: dotfiles-sync export, dotfiles-sync import...
    .EXAMPLE
        dotfiles-sync status
    #>
    $repo = if ($env:DOTFILES_SYNC_REPO) { $env:DOTFILES_SYNC_REPO } else { Join-Path $HOME 'dotfiles' }

    if ($global:_OS -eq 'windows') {
        $script = Join-Path $repo 'scripts\dotfiles-sync.ps1'
        if (-not (Test-Path -LiteralPath $script)) {
            Write-Error "dotfiles-sync: $script not found (set `$env:DOTFILES_SYNC_REPO)"
            return
        }
        $pwsh = if ($PSVersionTable.PSVersion.Major -ge 7) { (Get-Process -Id $PID).Path } else { 'pwsh' }
        & $pwsh -NoProfile -File $script -C $repo @args
        return
    }

    $script = Join-Path $repo 'scripts/dotfiles-sync.sh'
    if (-not (Test-Path -LiteralPath $script)) {
        Write-Error "dotfiles-sync: $script not found (set `$env:DOTFILES_SYNC_REPO)"
        return
    }
    & bash $script -C $repo @args
}

# shell integrations
if (Get-Command fzf -ErrorAction SilentlyContinue) {
    try { 
        $out = & fzf --powershell 2>$null | Out-String
        if (-not [string]::IsNullOrWhiteSpace($out)) { Invoke-Expression $out }
    } catch { }
}
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    try {
        $out = & zoxide init powershell 2>$null | Out-String
        if (-not [string]::IsNullOrWhiteSpace($out)) { Invoke-Expression $out }
    } catch { }
}
if (Get-Command mole -ErrorAction SilentlyContinue) {
    try { 
        $out = & mole completion powershell 2>$null | Out-String
        if (-not [string]::IsNullOrWhiteSpace($out)) { Invoke-Expression $out }
    } catch { }
}
if (Get-Command carapace -ErrorAction SilentlyContinue) {
    try {
        $env:CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
        Set-PSReadLineOption -Colors @{ "Selection" = "`e[7m" }
        Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete
        carapace _carapace powershell | Out-String | Invoke-Expression
    } catch { }
}

## inside a session: persist the cwd and refresh the status line on every
## directory change - the equivalent of the chpwd hook in .zshrc. The previous
## handler is captured and called first so this chains onto zoxide's hook rather
## than replacing it.
if ($env:TMUX -and $env:PSMUX_SESSION) {
    try { Start-PsmuxStatsDaemon } catch { }
    try { Start-PsmuxAutosave } catch { }

    $global:_PsmuxPwdFile          = Get-PsmuxPwdFile $env:PSMUX_SESSION
    $global:_PsmuxPrevLocationHook = $ExecutionContext.SessionState.InvokeCommand.LocationChangedAction

    $ExecutionContext.SessionState.InvokeCommand.LocationChangedAction = {
        param($Source, $EventArgs)

        if ($global:_PsmuxPrevLocationHook) {
            try { & $global:_PsmuxPrevLocationHook $Source $EventArgs } catch { }
        }
        try {
            Set-Content -LiteralPath $global:_PsmuxPwdFile -Value $EventArgs.NewPath.Path -Encoding utf8
            & psmux refresh-client -S 2>$null | Out-Null
        } catch { }
    }
}

# Configure PSReadLine for better interactive experience (similar to zsh-autosuggestions/syntax-highlighting)
Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Module PSReadLine) {
    # Inline suggestions (the zsh-autosuggestions equivalent).
    #
    # Setting this here alone is not enough: PSReadLine resets PredictionSource
    # to None somewhere between the profile finishing and the first interactive
    # prompt. Measured in a psmux pane - `pwsh -Command` reports History at the
    # end of the profile, while the live prompt in the same setup reports None,
    # and re-applying the option by hand at that prompt makes suggestions appear
    # immediately. So set it twice: once here, and once more on the first idle,
    # which happens after the reset. MaxTriggerCount makes that a one-shot.
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle InlineView -ErrorAction Stop
    } catch { }

    $null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
        try {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle InlineView
        } catch { }
    }

    # No audible bell. PSReadLine beeps on its own for a failed or ambiguous
    # completion, independently of the terminal's bell setting, so silencing it
    # here is what actually stops the beeping on Tab.
    try { Set-PSReadLineOption -BellStyle None -ErrorAction Stop } catch { }

    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    
    # Word motions.
    #
    # .config/komorebi/komorebic-hotkeys.ahk rewrites Alt+Arrow to Ctrl+Arrow
    # system-wide ("Option + Arrows -> Ctrl + Arrows"), so pressing Alt+Left in a
    # terminal delivers Ctrl+Left and the Alt+LeftArrow handler below is never
    # reached. Binding Ctrl+Arrow to line-start/end therefore made Alt+Arrow jump
    # to the start of the line instead of a word.
    #
    # .zshrc resolves this by binding both encodings - \e[1;3D (Alt) and \e[1;5D
    # (Ctrl) - to the same word motion, and leaving Home/End for line ends. Same
    # thing here, so the chord behaves identically whichever shell it lands in.
    # Forward is ForwardWord, not NextWord: when an inline suggestion is showing
    # it accepts the next word of it (zsh-autosuggestions' partial accept), and
    # with no suggestion it still moves a word. AcceptNextSuggestionWord does the
    # first half only and is inert the rest of the time, so it is the worse pick.
    Set-PSReadLineKeyHandler -Key 'Ctrl+d' -Function DeleteCharOrExit
    Set-PSReadLineKeyHandler -Key Alt+LeftArrow -Function BackwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow -Function BackwardWord
    Set-PSReadLineKeyHandler -Key Alt+RightArrow -Function ForwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord

    # Delete back one word, stopping on the delimiters set below - so
    # `foo bar_baz` loses only `baz`. Alt+Backspace arrives as ESC DEL, which
    # this handler catches; AHK leaves the chord alone (it only remaps
    # Win+Backspace to Delete).
    Set-PSReadLineKeyHandler -Key Alt+Backspace -Function BackwardKillWord
    Set-PSReadLineKeyHandler -Key Home -Function BeginningOfLine
    Set-PSReadLineKeyHandler -Key End -Function EndOfLine

    # Stop word motions on punctuation too. .zshrc sets WORDCHARS='' so every
    # non-alphanumeric character is a boundary; PSReadLine's default delimiter
    # set omits _ ~ @ # $ % < > and the backtick, which is why jumps overshot
    # through things like paths and variable names.
    try {
        Set-PSReadLineOption -WordDelimiters ';:,.[]{}()/\|!?^&*-=+_''"`~@#$%<>–—―' -ErrorAction Stop
    } catch { }

    # History search
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key 'Ctrl+r' -Function ReverseSearchHistory
    Set-PSReadLineKeyHandler -Key 'Ctrl+s' -Function ForwardSearchHistory
}

# machine-specific settings kept outside the repo (see .syncignore)
$localProfile = Join-Path $env:USERPROFILE 'profile.local.ps1'
if (Test-Path -LiteralPath $localProfile) { . $localProfile }
