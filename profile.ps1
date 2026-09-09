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
if (Get-Command starship -ErrorAction SilentlyContinue) {
    & starship init powershell | Out-String | Invoke-Expression
}

# fzf
$env:FZF_DEFAULT_OPTS = '--color=bg:#282828,bg+:#3c3836 --color=fg:#ebdbb2,fg+:#fbf1c7 --color=hl:#83a598,hl+:#8ec07c --color=info:#fabd2f,prompt:#fabd2f,pointer:#fe8019 --color=marker:#b8bb26,spinner:#8ec07c,header:#83a598 --layout=reverse-list'

# yazi
function y {
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

# editor
$env:EDITOR = "nvim"
$env:VISUAL = $env:EDITOR

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
function ld { lazydocker @args }
function open { start @args }
function c { Clear-Host }

function ua { npx tsx "$env:USERPROFILE\dotfiles\scripts\run-tasks\run-tasks.ts" "$env:USERPROFILE\dotfiles\scripts\run-tasks\update-$($global:_OS).yaml" }

# claude code aliases
function cc { claude --dangerously-skip-permissions @args }
function ccs { & "$env:USERPROFILE\dotfiles\scripts\ccswitch.ps1" @args }
function ccl { ccs --list }
function cc1 { ccs --switch-to 1; cc @args }
function cc2 { ccs --switch-to 2; cc @args }

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

## inside a session: persist the cwd and refresh the status line on every
## directory change - the equivalent of the chpwd hook in .zshrc. The previous
## handler is captured and called first so this chains onto zoxide's hook rather
## than replacing it.
if ($env:TMUX -and $env:PSMUX_SESSION) {
    try { Start-PsmuxStatsDaemon } catch { }

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

## auto-start psmux when opening a new Windows Terminal tab, mirroring the WSL
## auto-launch block in .zshrc. Skipped inside an existing session (psmux sets
## TMUX in its panes), outside Windows Terminal, and in non-interactive hosts.
if ($env:WT_SESSION -and
    -not $env:TMUX -and
    $Host.Name -eq 'ConsoleHost' -and
    (Get-Command psmux -ErrorAction SilentlyContinue)) {

    try {
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
