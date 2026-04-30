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
function cc { claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official @args }
function ccs { bash "$env:USERPROFILE\dotfiles\scripts\ccswitch.sh" @args }
function ccl { ccs --list }
function cc1 { ccs --switch-to 1; cc }
function cc2 { ccs --switch-to 2; cc }

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
        $env:CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense'
        $out = & carapace _carapace powershell 2>$null | Out-String
        if (-not [string]::IsNullOrWhiteSpace($out)) { Invoke-Expression $out }
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

# Configure PSReadLine for better interactive experience (similar to zsh-autosuggestions/syntax-highlighting)
Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Module PSReadLine) {
    try {
        try {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction Stop
        } catch {
            Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        }
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    } catch { }
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    
    # macOS-like keybindings
    Set-PSReadLineKeyHandler -Key 'Ctrl+d' -Function DeleteCharOrExit
    Set-PSReadLineKeyHandler -Key Alt+LeftArrow -Function BackwardWord
    Set-PSReadLineKeyHandler -Key Alt+RightArrow -Function ForwardWord
    Set-PSReadLineKeyHandler -Key Alt+Backspace -Function BackwardKillWord

    # History search
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key 'Ctrl+r' -Function ReverseSearchHistory
    Set-PSReadLineKeyHandler -Key 'Ctrl+s' -Function ForwardSearchHistory
}
