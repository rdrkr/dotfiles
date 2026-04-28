<#
.SYNOPSIS
    Cross-platform dotfiles installer for native Windows.

.DESCRIPTION
    Manages dotfiles restore, backup, and scheduled backups using winget
    and PowerShell symlinks. This is the Windows-native counterpart to
    install.sh (which covers macOS, Linux, and WSL).

    Can be run as a one-liner to bootstrap a fresh machine:
      irm https://raw.githubusercontent.com/rdrkr/dotfiles/main/install.ps1 | iex

.PARAMETER Command
    The action to perform: restore, backup, or schedule.

.PARAMETER DryRun
    Run in dry-run mode without making any changes.

.EXAMPLE
    .\install.ps1 restore
    .\install.ps1 backup -DryRun
    .\install.ps1 schedule
#>

param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Alias("d")]
    [switch]$DryRun,

    [Alias("h")]
    [switch]$Help
)

# --- Configuration ---
$ESC = [char]27
$NC = "$($ESC)[0m"
$C_LAVENDER = "$($ESC)[38;2;180;190;254m"
$C_BLUE = "$($ESC)[38;2;137;180;250m"
$C_PEACH = "$($ESC)[38;2;250;179;135m"

# Enable ANSI colors for Windows PowerShell (5.1)
if ($PSVersionTable.PSVersion.Major -le 5) {
    try {
        $Signature = @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        $null = Add-Type -MemberDefinition $Signature -Name "Win32" -Namespace "Win32" -ErrorAction SilentlyContinue
        $handle = [Win32.Win32]::GetStdHandle(-11) # STDOUT
        $mode = 0
        if ([Win32.Win32]::GetConsoleMode($handle, [ref]$mode)) {
            $null = [Win32.Win32]::SetConsoleMode($handle, $mode -bor 4)
        }
    } catch { }
}

$ValidCommands = @("restore", "backup", "schedule", "help")
if ($Command -and $Command -notin $ValidCommands) {
    Write-Host "${C_PEACH}X Invalid command: $Command. Valid commands are: $($ValidCommands -join ', ')${NC}"
    exit 1
}

# --- Admin Gate ---
# Require elevation upfront for any command that changes system state.
# Developer Mode, wsl --install, and some winget packages all need admin;
# a single early check produces one clear message instead of per-step
# warnings mid-run. Skipped for help/dry-run since those don't mutate.
$needsAdmin = if ($Command) { $Command -in @("restore", "backup", "schedule") } else { $true }
if ($needsAdmin -and -not $Help -and -not $DryRun) {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "${C_PEACH}X This script must be run from an Administrator PowerShell.${NC}"
        Write-Host "${C_YELLOW}! Right-click 'Windows Terminal' (or 'PowerShell') and pick 'Run as Administrator', then re-run:${NC}"
        Write-Host "    irm `"https://raw.githubusercontent.com/rdrkr/dotfiles/main/install.ps1`" | iex"
        return
    }
}

$DotfilesDir = Join-Path $env:USERPROFILE "dotfiles"
$DotfilesRepo = "https://github.com/rdrkr/dotfiles.git"

# Force wsl.exe to emit UTF-8 instead of UTF-16 LE. Without this, commands
# like `wsl --list --quiet` return strings riddled with NUL bytes that break
# regex/string comparisons in PowerShell.
$env:WSL_UTF8 = "1"

# --- Bootstrap ---
# When invoked remotely (irm ... | iex), $MyInvocation.MyCommand.Definition
# will not point to a file inside the repo. Detect this and bootstrap.
function Test-IsLocal {
    $scriptPath = $MyInvocation.ScriptName
    if (-not $scriptPath) { return $false }
    $parentDir = Split-Path -Parent $scriptPath
    return (Test-Path (Join-Path $parentDir ".git"))
}

function Wait-ForExit {
    <#
    .SYNOPSIS
        Pauses so the user can read output before the window closes.
        Falls back to Read-Host when the host doesn't support RawUI.ReadKey
        (e.g., ISE, VS Code integrated terminal).
    #>
    param([string]$Message = "Press Enter to close...")
    Write-Host ""
    Write-Host $Message
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    catch {
        $null = Read-Host
    }
}

function Invoke-Bootstrap {
    <#
    .SYNOPSIS
        Installs git via winget, clones the repo, and re-executes locally.

    .NOTES
        Uses `return` instead of `exit` throughout. When this script is run
        via `irm ... | iex`, calling `exit` terminates the user's interactive
        PowerShell session (closing the terminal window). Returning instead
        just stops the bootstrap scriptblock and leaves the session alive.
    #>
    Write-Host "${C_BLUE}=== Bootstrapping dotfiles ===${NC}"

    # Ensure winget is available
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "${C_PEACH}X winget not found. Please install App Installer from the Microsoft Store.${NC}"
        return
    }

    # Install git if missing
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Installing git..."
        winget install --id Git.Git --accept-package-agreements --accept-source-agreements --silent
        # Refresh PATH so git is available in this session
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    }

    # Clone or pull
    if (Test-Path (Join-Path $DotfilesDir ".git")) {
        Write-Host "Dotfiles repo already exists. Pulling latest changes..."
        git -C $DotfilesDir pull origin main
        if ($LASTEXITCODE -ne 0) {
            Write-Host "${C_PEACH}X Failed to pull latest changes.${NC}"
            return
        }
    }
    else {
        Write-Host "Cloning dotfiles repo..."
        git clone $DotfilesRepo $DotfilesDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "${C_PEACH}X Failed to clone dotfiles repo.${NC}"
            # Attempt to fix partial clone/checkout if it failed due to paths (e.g. symlinks)
            if (Test-Path $DotfilesDir) {
                 Write-Host "Attempting to restore checkout..."
                 git -C $DotfilesDir restore --source=HEAD :/
            }

            if (-not (Test-Path (Join-Path $DotfilesDir "install.ps1"))) {
                 Write-Host "${C_PEACH}X Bootstrap failed: Repo cloned but checkout is incomplete.${NC}"
                 return
            }
        }
    }

    # Re-execute from the cloned repo
    $localScript = Join-Path $DotfilesDir "install.ps1"
    if (-not (Test-Path $localScript)) {
        Write-Host "${C_PEACH}X Could not find local install.ps1 at $localScript. Bootstrap failed.${NC}"
        return
    }

    Write-Host "Handing off to local install.ps1..."
    $effectiveCommand = if ($Command) { $Command } else { "restore" }

    # Try pwsh first, then powershell.exe
    $exe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell.exe" }

    # Use -File to avoid ampersand parser issues. -ExecutionPolicy Bypass ensures it runs.
    if ($exe -eq "pwsh") {
        pwsh -NoProfile -ExecutionPolicy Bypass -File "$localScript" $effectiveCommand
    }
    else {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$localScript" $effectiveCommand
    }

    $childExit = $LASTEXITCODE
    if ($childExit -ne 0) {
        Write-Host "${C_PEACH}X Local execution failed with exit code $childExit.${NC}"
    }
    # Intentionally no `exit` here -- returning normally keeps the caller's
    # interactive session (and its terminal window) open.
}

if (-not (Test-IsLocal)) {
    try {
        Invoke-Bootstrap
    }
    catch {
        Write-Host "${C_PEACH}X A bootstrap error occurred: $($_.Exception.Message)${NC}"
    }
    # Stop here -- the rest of this file expects to run from a cloned repo
    # on disk, which is not the case when invoked via `irm | iex`.
    # `return` at script scope ends the iex scriptblock without closing
    # the user's PowerShell session.
    return
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$WingetPackagesFile = Join-Path $ScriptDir ".config\winget-packages.txt"
$ScoopBucketsFile = Join-Path $ScriptDir ".config\scoop-buckets.txt"
$ScoopPackagesFile = Join-Path $ScriptDir ".config\scoop-packages.txt"
$NpmGlobalFile = Join-Path $ScriptDir ".config\npm-global-packages.txt"
$PipxPackagesFile = Join-Path $ScriptDir ".config\pipx-packages.txt"
$BunPackagesFile = Join-Path $ScriptDir ".config\bun-packages.txt"
$PersonalizationRegFile = Join-Path $ScriptDir ".config\windows-personalization.reg"
$StartupRegFile = Join-Path $ScriptDir ".config\windows-startup.reg"
$StartupFolderDir = Join-Path $ScriptDir ".config\windows-startup"
$WindowsTerminalConfigDir = Join-Path $ScriptDir ".config\windows-terminal"
$WindowsTerminalLocalState = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
$WallpapersDir = Join-Path $ScriptDir ".wallpapers"
$DotfilesTarget = $env:USERPROFILE

# --- Colors (ANSI escape sequences) ---
$C_SAPPHIRE = "$($ESC)[38;2;116;199;236m"
$C_SKY = "$($ESC)[38;2;137;220;235m"
$C_TEAL = "$($ESC)[38;2;148;226;213m"
$C_GREEN = "$($ESC)[38;2;166;227;161m"
$C_YELLOW = "$($ESC)[38;2;249;226;175m"

# --- Logo ---
function Print-Logo {
    Write-Host "${C_LAVENDER} ____        _    __ _ _           ${NC}"
    Write-Host "${C_BLUE}|  _ \  ___ | |_ / _(_) | ___  ___ ${NC}"
    Write-Host "${C_SAPPHIRE}| | | |/ _ \| __| |_| | |/ _ \/ __|${NC}"
    Write-Host "${C_SKY}| |_| | (_) | |_|  _| | |  __/\__ \ ${NC}"
    Write-Host "${C_TEAL}|____/ \___/ \__|_| |_|_|\___||___/${NC}"
    Write-Host ""
}

# --- Utility Functions ---
function Print-Header {
    param([string]$Message)
    Write-Host "${C_BLUE}=================================================${NC}"
    Write-Host "${C_LAVENDER} $Message ${NC}"
    Write-Host "${C_BLUE}=================================================${NC}"
}

function Print-Success {
    param([string]$Message)
    Write-Host "${C_GREEN}+ $Message${NC}"
}

function Print-Warning {
    param([string]$Message)
    Write-Host "${C_YELLOW}! $Message${NC}"
}

function Print-Error {
    param([string]$Message)
    Write-Host "${C_PEACH}X $Message${NC}"
}

function Print-Help {
    Print-Logo
    Write-Host 'Usage: .\install.ps1 <command> [options]'
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  restore      Restore dotfiles and install dependencies"
    Write-Host "  backup       Update package lists with current setup"
    Write-Host "  schedule     Schedule hourly backups using Task Scheduler"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Help, -h       Show this help message and exit"
    Write-Host "  -DryRun, -d     Run in dry-run mode (no changes will be made)"
}

function Run-Command {
    <#
    .SYNOPSIS
        Executes a command or prints it in dry-run mode.
    #>
    param([string]$Cmd)
    if ($DryRun) {
        Write-Host "${C_YELLOW}`[DRY RUN`] Would execute: $Cmd${NC}"
    }
    else {
        Invoke-Expression $Cmd
    }
}

# --- Symlink Creation (stow alternative) ---
function Get-StowIgnorePatterns {
    <#
    .SYNOPSIS
        Parses .stowrc at the repo root and returns user-supplied ignore
        regex patterns.

    .DESCRIPTION
        Each `--ignore=<regex>` line contributes one pattern. Blank lines and
        comments (`#`) are skipped. Matches GNU Stow's semantics: each pattern
        is a regex matched against a path's basename.
    #>
    $stowrc = Join-Path $ScriptDir ".stowrc"
    if (-not (Test-Path $stowrc)) { return @() }

    $patterns = @()
    foreach ($line in Get-Content $stowrc) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^--ignore=(.+)$') {
            $patterns += $matches[1].Trim()
        }
    }
    return $patterns
}

function Create-Symlinks {
    <#
    .SYNOPSIS
        Creates symlinks from the dotfiles directory into the user's home,
        mirroring what GNU Stow does on Unix systems.
    #>
    Print-Header "Creating symlinks..."

    # Windows privilege strategy:
    #   - Directories -> Junction (no admin, no Developer Mode required)
    #   - Files       -> HardLink (no admin required on NTFS)
    # SymbolicLink is avoided because it requires admin OR Developer Mode on Windows.
    #
    # Layout strategy (mirrors stow on Unix):
    #   - .config/* is expanded per-child so ~/.config can coexist with non-repo tools
    #   - All other top-level directories are junctioned whole into $HOME
    #   - Top-level files are hardlinked into $HOME
    # Ignore list has two layers, mirroring GNU Stow:
    #   1. Built-in defaults: VCS metadata + README/LICENSE (stow always
    #      ignores these regardless of .stowrc).
    #   2. User patterns from .stowrc (each `--ignore=<regex>` line). Stow
    #      treats each ignore entry as a regex matched against the basename.
    $builtinIgnoreRegex = @(
        '^\.git$', '^\.gitignore$', '^\.gitmodules$',
        '^RCS$', '^CVS$', '^\.svn$', '^_darcs$', '^\.hg$',
        '^README.*', '^LICENSE.*', '^COPYING$',
        '^\.DS_Store$'
    )
    $userIgnoreRegex = Get-StowIgnorePatterns
    $allIgnoreRegex = $builtinIgnoreRegex + $userIgnoreRegex

    function Test-IsIgnored([string]$name) {
        foreach ($pat in $allIgnoreRegex) {
            if ($name -match $pat) { return $true }
        }
        return $false
    }

    # Helper: create a junction at $dest pointing to $src.
    function New-JunctionLink($dest, $src, $label) {
        if (Test-Path $dest) {
            Print-Warning "Already exists, skipping: $dest"
            $script:skipped++
            return
        }
        if ($DryRun) {
            Print-Warning "`[DRY RUN`] Would link: $dest -> $src"
            return
        }
        try {
            New-Item -ItemType Junction -Path $dest -Target $src -ErrorAction Stop | Out-Null
            Print-Success "Linked: $dest -> $src"
            $script:linked++
        }
        catch {
            Print-Error "Failed to link ${label}: $($_.Exception.Message)"
            $script:failed++
        }
    }

    # Helper: create a hardlink at $dest pointing to $src.
    function New-FileLink($dest, $src, $label) {
        if (Test-Path $dest) {
            Print-Warning "Already exists, skipping: $dest"
            $script:skipped++
            return
        }
        if ($DryRun) {
            Print-Warning "`[DRY RUN`] Would link: $dest -> $src"
            return
        }
        try {
            New-Item -ItemType HardLink -Path $dest -Target $src -ErrorAction Stop | Out-Null
            Print-Success "Linked: $dest -> $src"
            $script:linked++
        }
        catch {
            Print-Error "Failed to link ${label}: $($_.Exception.Message)"
            $script:failed++
        }
    }

    $script:linked = 0
    $script:skipped = 0
    $script:failed = 0

    $topLevel = Get-ChildItem -Path $ScriptDir -Force | Where-Object { -not (Test-IsIgnored $_.Name) }

    foreach ($item in $topLevel) {
        if ($item.Name -eq ".config" -and $item.PSIsContainer) {
            # Special: iterate children of .config so ~/.config can host links
            # from this repo alongside directories created by other tools.
            #   - Subdirectories (e.g. .config/glazewm)  -> Junction
            #   - Loose files    (e.g. .config/Brewfile, *.txt) -> HardLink
            $configTarget = Join-Path $DotfilesTarget ".config"
            if (-not $DryRun -and -not (Test-Path $configTarget)) {
                New-Item -ItemType Directory -Path $configTarget -Force | Out-Null
            }
            foreach ($child in Get-ChildItem -Path $item.FullName -Force) {
                if (Test-IsIgnored $child.Name) { continue }
                $dest = Join-Path $configTarget $child.Name
                if ($child.PSIsContainer) {
                    New-JunctionLink $dest $child.FullName $child.Name
                }
                else {
                    New-FileLink $dest $child.FullName $child.Name
                }
            }
        }
        elseif ($item.PSIsContainer) {
            # Other top-level directory: junction whole thing into $HOME
            New-JunctionLink (Join-Path $DotfilesTarget $item.Name) $item.FullName $item.Name
        }
        else {
            # Top-level file: hardlink into $HOME
            New-FileLink (Join-Path $DotfilesTarget $item.Name) $item.FullName $item.Name
        }
    }

    Print-Success "Symlinks: $($script:linked) linked, $($script:skipped) skipped, $($script:failed) failed."
    if ($script:failed -gt 0) {
        throw "Symlink creation had $($script:failed) failure(s)."
    }
}

# --- Developer Mode ---
function Test-IsAdmin {
    <#
    .SYNOPSIS
        Returns $true if the current session is elevated (Administrator).
    #>
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Enable-DeveloperMode {
    <#
    .SYNOPSIS
        Enables Windows Developer Mode by setting the AppModelUnlock flag in
        HKLM. Developer Mode lets non-admin users create SymbolicLinks and
        enables sideloading; it's a one-time, machine-scope flip.
    #>
    Print-Header "Enabling Windows Developer Mode..."
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    $valueName = "AllowDevelopmentWithoutDevLicense"

    $current = Get-ItemProperty -Path $regPath -Name $valueName -ErrorAction SilentlyContinue
    if ($current -and $current.$valueName -eq 1) {
        Print-Success "Developer Mode is already enabled."
        return
    }

    if ($DryRun) {
        Print-Warning "`[DRY RUN`] Would set $regPath\$valueName = 1 (enables Developer Mode)."
        return
    }

    try {
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -Path $regPath -Name $valueName -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
        Print-Success "Developer Mode enabled."
    }
    catch {
        Print-Error "Failed to enable Developer Mode: $($_.Exception.Message)"
    }
}

# --- Windows Theme ---
function Apply-WindowsTheme {
    <#
    .SYNOPSIS
        Applies the gruvbox .deskthemepack and sets the desktop wallpaper.

    .DESCRIPTION
        `.deskthemepack` is a self-extracting theme bundle. Launching it with
        the default handler opens Settings and applies the theme silently on
        modern Windows. The wallpaper is also set explicitly via the Win32
        SystemParametersInfo SPI, so the desired background is used even if
        the theme doesn't bundle it.
    #>
    Print-Header "Applying Windows theme..."
    $themeFile = Join-Path $ScriptDir ".win-themes\gruvbox-win-theme.deskthemepack"
    $wallpaperFile = Join-Path $ScriptDir ".wallpapers\BFD78173-A38C-4F68-BA51-06ED0CFD1B24_1_105_c.jpeg"

    # 1. Apply the .deskthemepack
    if (Test-Path $themeFile) {
        if ($DryRun) {
            Print-Warning "`[DRY RUN`] Would apply theme: $themeFile"
        }
        else {
            try {
                Start-Process -FilePath $themeFile -ErrorAction Stop
                Print-Success "Theme applied: $themeFile"
                # Theme application is async via Settings; give it a beat so
                # our SystemParametersInfo call below isn't overwritten.
                Start-Sleep -Seconds 3
            }
            catch {
                Print-Error "Failed to apply theme: $($_.Exception.Message)"
            }
        }
    }
    else {
        Print-Warning "Theme file not found: $themeFile. Skipping theme."
    }

    # 2. Set the wallpaper directly via Win32 SPI_SETDESKWALLPAPER (20).
    #    SPIF_UPDATEINIFILE (0x01) | SPIF_SENDCHANGE (0x02) = 3.
    if (Test-Path $wallpaperFile) {
        if ($DryRun) {
            Print-Warning "`[DRY RUN`] Would set wallpaper: $wallpaperFile"
        }
        else {
            try {
                if (-not ([System.Management.Automation.PSTypeName]'_DotfilesWallpaper').Type) {
                    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class _DotfilesWallpaper {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
                }
                [_DotfilesWallpaper]::SystemParametersInfo(20, 0, $wallpaperFile, 3) | Out-Null
                Print-Success "Wallpaper set: $wallpaperFile"
            }
            catch {
                Print-Error "Failed to set wallpaper: $($_.Exception.Message)"
            }
        }
    }
    else {
        Print-Warning "Wallpaper not found: $wallpaperFile. Skipping wallpaper."
    }
}

# --- Windows Personalization (Registry) ---
# Registry subtrees captured for modern (Win10/11) Personalization state.
# `.deskthemepack` handles classic theme bits (wallpaper, named colors,
# cursors, sounds) but NOT accent/DWM colorization, light/dark mode,
# transparency, taskbar alignment, etc. Those live in HKCU and round-trip
# cleanly through reg export/import.
$PersonalizationKeys = @(
    "HKCU\Control Panel\Colors",
    "HKCU\Control Panel\Cursors",
    "HKCU\Control Panel\Desktop\WindowMetrics",
    "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize",
    "HKCU\SOFTWARE\Microsoft\Windows\DWM",
    "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Accent",
    "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
)

# Registry subtrees that define per-user sign-in programs. Mirrors what Task
# Manager's Startup tab reads:
#   - Run: the entries themselves (command lines Windows launches at sign-in).
#   - StartupApproved\Run: enabled/disabled flag for each Run entry.
#   - StartupApproved\StartupFolder: enabled/disabled flag for shortcuts in
#     the Startup folder, which are mirrored separately to $StartupFolderDir.
$StartupKeys = @(
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"
)

function Backup-WindowsPersonalization {
    <#
    .SYNOPSIS
        Exports HKCU subtrees that hold modern Personalization state (accent
        color, light/dark mode, transparency, cursors, classic colors,
        window metrics, Explorer UI tweaks) into a single .reg file.

    .DESCRIPTION
        `reg export` emits UTF-16 LE with a
        "Windows Registry Editor Version 5.00" header per file. We export
        each key to a temp file, then concatenate by keeping the header
        from the first file and stripping it from the rest so the combined
        file is still a valid single .reg document for `reg import`.
    #>
    Print-Header "Backing up Windows personalization (registry)..."

    if ($DryRun) {
        foreach ($k in $PersonalizationKeys) {
            Print-Warning "`[DRY RUN`] Would export: $k"
        }
        Print-Warning "`[DRY RUN`] Would write combined file: $PersonalizationRegFile"
        return
    }

    $tmpFiles = @()
    try {
        foreach ($k in $PersonalizationKeys) {
            $tmp = [System.IO.Path]::GetTempFileName()
            & reg export $k $tmp /y *> $null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp) -and (Get-Item $tmp).Length -gt 0) {
                $tmpFiles += $tmp
            }
            else {
                Print-Warning "Could not export (may not exist on this machine): $k"
                if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
        }

        if ($tmpFiles.Count -eq 0) {
            Print-Warning "No registry subtrees exported. Skipping."
            return
        }

        # Keep the first file's header; drop the duplicate header from the rest.
        $combined = Get-Content -Path $tmpFiles[0] -Raw -Encoding Unicode
        for ($i = 1; $i -lt $tmpFiles.Count; $i++) {
            $body = Get-Content -Path $tmpFiles[$i] -Raw -Encoding Unicode
            $body = $body -replace '^Windows Registry Editor Version 5\.00\r?\n\r?\n', ''
            $combined += $body
        }

        $parent = Split-Path -Parent $PersonalizationRegFile
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        # Unicode encoding = UTF-16 LE with BOM, which is what `reg import` expects.
        Set-Content -Path $PersonalizationRegFile -Value $combined -Encoding Unicode -NoNewline
        Print-Success "Personalization registry backed up to $PersonalizationRegFile."
    }
    finally {
        foreach ($tmp in $tmpFiles) {
            if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Restore-WindowsPersonalization {
    <#
    .SYNOPSIS
        Imports the personalization .reg file so accent color, light/dark
        mode, transparency, cursors, and other modern Personalization
        settings match the backed-up state.

    .NOTES
        DWM accent and Explorer UI pick up some keys live; others (title
        bar tint, Start/taskbar accent) take effect on next sign-in.
    #>
    Print-Header "Restoring Windows personalization (registry)..."

    if (-not (Test-Path $PersonalizationRegFile)) {
        Print-Warning "$PersonalizationRegFile not found. Skipping."
        return
    }

    if ($DryRun) {
        Print-Warning "`[DRY RUN`] Would run: reg import $PersonalizationRegFile"
        return
    }

    & reg import $PersonalizationRegFile *> $null
    if ($LASTEXITCODE -eq 0) {
        Print-Success "Personalization registry imported."
        Print-Warning "Some settings (accent color, title bar tint) may need a sign-out to fully apply."
    }
    else {
        Print-Error "reg import exited with code $LASTEXITCODE."
    }
}

function Backup-WindowsLockScreen {
    <#
    .SYNOPSIS
        Copies the currently configured lock screen image into
        .wallpapers\lockscreen.<ext> so `restore` can pin the same image
        via PersonalizationCSP policy on another machine.

    .DESCRIPTION
        Source precedence:
          1. HKLM PersonalizationCSP\LockScreenImagePath (set by a prior
             `restore` or group policy).
          2. Newest image under the user's Microsoft.LockApp LocalState.
        If neither resolves, leaves the wallpapers dir alone and warns.
    #>
    Print-Header "Backing up lock screen image..."

    if (-not (Test-Path $WallpapersDir)) {
        if ($DryRun) {
            Print-Warning "`[DRY RUN`] Would create $WallpapersDir"
        }
        else {
            New-Item -ItemType Directory -Path $WallpapersDir -Force | Out-Null
        }
    }

    $source = $null

    # 1. PersonalizationCSP (policy-managed)
    $cspKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
    try {
        $cspPath = (Get-ItemProperty -Path $cspKey -Name "LockScreenImagePath" -ErrorAction Stop).LockScreenImagePath
        if ($cspPath -and (Test-Path $cspPath)) {
            $source = $cspPath
        }
    } catch { }

    # 2. Fallback: newest image in LockApp LocalState
    if (-not $source) {
        $lockAppDir = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.LockApp_cw5n1h2txyewy\LocalState"
        if (Test-Path $lockAppDir) {
            $candidate = Get-ChildItem -Path $lockAppDir -Recurse -Include *.jpg, *.jpeg, *.png -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($candidate) { $source = $candidate.FullName }
        }
    }

    if (-not $source) {
        Print-Warning "Could not detect a lock screen image. Drop one at .wallpapers\lockscreen.<ext> to set it on restore."
        return
    }

    $ext = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
    if (-not $ext) { $ext = ".jpg" }
    $dest = Join-Path $WallpapersDir ("lockscreen" + $ext)

    if ($DryRun) {
        Print-Warning "`[DRY RUN`] Would copy $source -> $dest"
        return
    }

    # Remove any stale lockscreen.* (different extension) before writing.
    Get-ChildItem -Path $WallpapersDir -Filter "lockscreen.*" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $dest } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    if ($source -ne $dest) {
        Copy-Item -Path $source -Destination $dest -Force
        Print-Success "Lock screen image backed up to $dest."
    } else {
        Print-Success "Lock screen image already backed up."
    }
}

function Apply-WindowsLockScreen {
    <#
    .SYNOPSIS
        Sets the machine-wide lock screen image via PersonalizationCSP
        policy, pointing at .wallpapers\lockscreen.<ext> from this repo.
        Falls back to the desktop wallpaper when no dedicated lock-screen
        asset exists.

    .NOTES
        PersonalizationCSP requires admin (guaranteed by the admin gate at
        the top of this script). Setting these keys makes the Settings
        lock-screen picker read-only; that's the intended behavior for a
        repo-managed configuration.
    #>
    Print-Header "Applying lock screen image..."

    $lockImage = $null
    if (Test-Path $WallpapersDir) {
        $lockImage = Get-ChildItem -Path $WallpapersDir -Filter "lockscreen.*" -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }

    if ($lockImage) {
        $imagePath = $lockImage.FullName
    }
    else {
        $fallback = Join-Path $WallpapersDir "BFD78173-A38C-4F68-BA51-06ED0CFD1B24_1_105_c.jpeg"
        if (Test-Path $fallback) {
            $imagePath = $fallback
            Print-Warning "No .wallpapers\lockscreen.* found; using desktop wallpaper as fallback."
        }
        else {
            Print-Warning "No lock screen or fallback wallpaper found. Skipping."
            return
        }
    }

    if ($DryRun) {
        Print-Warning "`[DRY RUN`] Would set PersonalizationCSP\LockScreenImagePath = $imagePath"
        return
    }

    $cspKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
    try {
        if (-not (Test-Path $cspKey)) {
            New-Item -Path $cspKey -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -Path $cspKey -Name "LockScreenImagePath"   -PropertyType String -Value $imagePath -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $cspKey -Name "LockScreenImageUrl"    -PropertyType String -Value $imagePath -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $cspKey -Name "LockScreenImageStatus" -PropertyType DWord  -Value 1          -Force -ErrorAction Stop | Out-Null
        Print-Success "Lock screen image set: $imagePath"
    }
    catch {
        Print-Error "Failed to set lock screen image: $($_.Exception.Message)"
    }
}

# --- Startup Applications ---
function Backup-WindowsStartup {
    <#
    .SYNOPSIS
        Exports HKCU Run keys and mirrors the user's Startup folder so
        sign-in-time programs are part of the dotfiles.

    .DESCRIPTION
        Two sources define what Windows runs at sign-in on a per-user basis:
          1. Registry Run entries (where modern apps register themselves).
          2. `.lnk` shortcuts under %APPDATA%\...\Startup (legacy, manual).
        StartupApproved subkeys ride along so restored entries keep their
        enabled/disabled state in Task Manager's Startup tab.

        The repo's Startup folder mirror is rebuilt from scratch on every
        backup so upstream deletions propagate.
    #>
    Print-Header "Backing up Windows startup applications..."

    # Part 1: registry. Same "export each key, stitch into one .reg" pattern
    # as Backup-WindowsPersonalization -- see its header for the rationale.
    if ($DryRun) {
        foreach ($k in $StartupKeys) {
            Print-Warning "`[DRY RUN`] Would export: $k"
        }
        Print-Warning "`[DRY RUN`] Would write combined file: $StartupRegFile"
    }
    else {
        $tmpFiles = @()
        try {
            foreach ($k in $StartupKeys) {
                $tmp = [System.IO.Path]::GetTempFileName()
                & reg export $k $tmp /y *> $null
                if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp) -and (Get-Item $tmp).Length -gt 0) {
                    $tmpFiles += $tmp
                }
                else {
                    Print-Warning "Could not export (may not exist on this machine): $k"
                    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
                }
            }

            if ($tmpFiles.Count -gt 0) {
                $combined = Get-Content -Path $tmpFiles[0] -Raw -Encoding Unicode
                for ($i = 1; $i -lt $tmpFiles.Count; $i++) {
                    $body = Get-Content -Path $tmpFiles[$i] -Raw -Encoding Unicode
                    $body = $body -replace '^Windows Registry Editor Version 5\.00\r?\n\r?\n', ''
                    $combined += $body
                }

                $parent = Split-Path -Parent $StartupRegFile
                if (-not (Test-Path $parent)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                Set-Content -Path $StartupRegFile -Value $combined -Encoding Unicode -NoNewline
                Print-Success "Startup registry backed up to $StartupRegFile."
            }
            else {
                Print-Warning "No startup registry subtrees exported."
            }
        }
        finally {
            foreach ($tmp in $tmpFiles) {
                if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    # Part 2: Startup folder shortcuts.
    $startupFolder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
    if (-not (Test-Path $startupFolder)) {
        Print-Warning "User Startup folder not found: $startupFolder."
        return
    }

    if ($DryRun) {
        Print-Warning "`[DRY RUN`] Would mirror $startupFolder -> $StartupFolderDir"
        return
    }

    if (-not (Test-Path $StartupFolderDir)) {
        New-Item -ItemType Directory -Path $StartupFolderDir -Force | Out-Null
    }

    # Rebuild the mirror so upstream deletions show up in git diff as removals.
    Get-ChildItem -Path $StartupFolderDir -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $items = Get-ChildItem -Path $startupFolder -Force -ErrorAction SilentlyContinue
    if ($items) {
        foreach ($item in $items) {
            Copy-Item -LiteralPath $item.FullName -Destination $StartupFolderDir -Force
        }
        Print-Success "Copied $($items.Count) startup folder item(s) to $StartupFolderDir."
    }
    else {
        Print-Success "Startup folder is empty."
    }
}

function Restore-WindowsStartup {
    <#
    .SYNOPSIS
        Imports HKCU Run keys and copies saved Startup folder shortcuts back
        into the user's Startup folder so sign-in programs match backup.

    .NOTES
        New Run entries apply on the next sign-in. `.lnk` files are copied
        additively -- we don't clear the Startup folder, since Windows and
        some apps drop system items there that aren't ours to manage.
    #>
    Print-Header "Restoring Windows startup applications..."

    # Part 1: registry.
    if (-not (Test-Path $StartupRegFile)) {
        Print-Warning "$StartupRegFile not found. Skipping registry restore."
    }
    elseif ($DryRun) {
        Print-Warning "`[DRY RUN`] Would run: reg import $StartupRegFile"
    }
    else {
        & reg import $StartupRegFile *> $null
        if ($LASTEXITCODE -eq 0) {
            Print-Success "Startup registry imported."
        }
        else {
            Print-Error "reg import exited with code $LASTEXITCODE."
        }
    }

    # Part 2: Startup folder shortcuts.
    if (-not (Test-Path $StartupFolderDir)) {
        Print-Warning "$StartupFolderDir not found. Skipping startup folder restore."
        return
    }

    $startupFolder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"

    if ($DryRun) {
        Print-Warning "`[DRY RUN`] Would copy shortcuts from $StartupFolderDir -> $startupFolder"
        return
    }

    if (-not (Test-Path $startupFolder)) {
        New-Item -ItemType Directory -Path $startupFolder -Force | Out-Null
    }

    $items = Get-ChildItem -Path $StartupFolderDir -Force -ErrorAction SilentlyContinue
    $count = 0
    foreach ($item in $items) {
        $dest = Join-Path $startupFolder $item.Name
        Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
        $count++
    }
    if ($count -gt 0) {
        Print-Success "Copied $count startup folder item(s) to $startupFolder."
    }
    else {
        Print-Warning "No startup folder items to restore."
    }
}

# --- PowerShell Profile ---
function Link-PowerShellProfile {
    <#
    .SYNOPSIS
        Dot-sources the repo's profile.ps1 in the user's PowerShell profiles.
    #>
    Print-Header "Linking PowerShell profile..."

    $repoProfile = Join-Path $ScriptDir "profile.ps1"
    if (-not (Test-Path $repoProfile)) {
        Print-Warning "profile.ps1 not found at $repoProfile. Skipping profile link."
        return
    }

    # Support both Windows PowerShell 5.1 and PowerShell Core 7+
    $docsPath = [Environment]::GetFolderPath('MyDocuments')
    $profilePaths = @(
        (Join-Path $docsPath "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"),
        (Join-Path $docsPath "PowerShell\Microsoft.PowerShell_profile.ps1")
    )

    foreach ($dest in $profilePaths) {
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path $destDir)) {
            if ($DryRun) {
                Print-Warning "`[DRY RUN`] Would create directory: $destDir"
            } else {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
        }

        if ($DryRun) {
            Print-Warning "`[DRY RUN`] Would dot-source $repoProfile in $dest"
            continue
        }

        try {
            $sourceLine = ". `"$repoProfile`""
            if (Test-Path $dest) {
                $content = Get-Content $dest -Raw
                if ($content -notmatch [regex]::Escape($sourceLine)) {
                    Add-Content -Path $dest -Value "`n$sourceLine"
                    Print-Success "Added dot-source to existing profile: $dest"
                } else {
                    Print-Success "Profile already dot-sources repo profile: $dest"
                }
            } else {
                Set-Content -Path $dest -Value $sourceLine
                Print-Success "Created new profile dot-sourcing repo profile: $dest"
            }
        }
        catch {
            Print-Error "Failed to set up profile at ${dest}: $($_.Exception.Message)"
        }
    }
}

# --- Windows Terminal ---
function Link-WindowsTerminalSettings {
    <#
    .SYNOPSIS
        Hardlinks each file in .config/windows-terminal/ into the Windows
        Terminal LocalState folder so edits to settings.json flow back to
        the repo automatically.

    .NOTES
        Same privilege strategy as Create-Symlinks for files: HardLink,
        which works on NTFS without admin or Developer Mode. Windows
        Terminal edits settings.json in place, so the two paths continue
        to share an inode across saves.

        If a file already exists at the target:
          - Identical content -> delete + relink (guarantees hardlink sharing).
          - Different content -> move aside as .bak, then link.
    #>
    Print-Header "Linking Windows Terminal settings..."

    if (-not (Test-Path $WindowsTerminalConfigDir)) {
        Print-Warning "$WindowsTerminalConfigDir not found. Skipping terminal settings link."
        return
    }

    $sources = Get-ChildItem -Path $WindowsTerminalConfigDir -File -Force -ErrorAction SilentlyContinue
    if (-not $sources) {
        Print-Warning "$WindowsTerminalConfigDir is empty. Skipping."
        return
    }

    if ($DryRun) {
        foreach ($src in $sources) {
            Print-Warning "`[DRY RUN`] Would hardlink $($src.FullName) -> $WindowsTerminalLocalState\$($src.Name)"
        }
        return
    }

    if (-not (Test-Path $WindowsTerminalLocalState)) {
        New-Item -ItemType Directory -Path $WindowsTerminalLocalState -Force | Out-Null
    }

    foreach ($src in $sources) {
        $dest = Join-Path $WindowsTerminalLocalState $src.Name
        try {
            if (Test-Path $dest) {
                $srcHash = (Get-FileHash -LiteralPath $src.FullName).Hash
                $dstHash = (Get-FileHash -LiteralPath $dest).Hash
                if ($srcHash -eq $dstHash) {
                    Remove-Item -LiteralPath $dest -Force
                }
                else {
                    $bak = "$dest.bak"
                    Move-Item -LiteralPath $dest -Destination $bak -Force
                    Print-Warning "Existing $dest backed up to $bak."
                }
            }
            New-Item -ItemType HardLink -Path $dest -Target $src.FullName -ErrorAction Stop | Out-Null
            Print-Success "Linked: $dest -> $($src.FullName)"
        }
        catch {
            Print-Error "Failed to link $($src.Name): $($_.Exception.Message)"
        }
    }
}

function Backup-WindowsTerminalSettings {
    <#
    .SYNOPSIS
        Copies Windows Terminal settings.json from LocalState into
        .config/windows-terminal/ so the repo owns the source of truth.

    .DESCRIPTION
        After a restore, settings.json in LocalState is hardlinked to the
        repo copy -- edits propagate automatically and this is a no-op.
        Before the first restore (or if the link was ever broken by an
        atomic rename), the two files diverge; we copy LocalState -> repo
        only when hashes differ, which preserves the hardlink when intact.
    #>
    Print-Header "Backing up Windows Terminal settings..."

    $liveSettings = Join-Path $WindowsTerminalLocalState "settings.json"
    if (-not (Test-Path $liveSettings)) {
        Print-Warning "Windows Terminal settings.json not found at $liveSettings. Skipping."
        return
    }

    if ($DryRun) {
        Print-Warning "`[DRY RUN`] Would sync $liveSettings -> $WindowsTerminalConfigDir\settings.json (if changed)."
        return
    }

    if (-not (Test-Path $WindowsTerminalConfigDir)) {
        New-Item -ItemType Directory -Path $WindowsTerminalConfigDir -Force | Out-Null
    }

    $repoSettings = Join-Path $WindowsTerminalConfigDir "settings.json"
    $needCopy = $true
    if (Test-Path $repoSettings) {
        $liveHash = (Get-FileHash -LiteralPath $liveSettings).Hash
        $repoHash = (Get-FileHash -LiteralPath $repoSettings).Hash
        if ($liveHash -eq $repoHash) { $needCopy = $false }
    }

    if ($needCopy) {
        Copy-Item -LiteralPath $liveSettings -Destination $repoSettings -Force
        Print-Success "Windows Terminal settings.json synced to $repoSettings."
    }
    else {
        Print-Success "Windows Terminal settings.json already in sync."
    }
}

function Set-XdgConfigHome {
    <#
    .SYNOPSIS
        Persists XDG_CONFIG_HOME as a user-scope environment variable pointing
        at %USERPROFILE%\.config (the junction Create-Symlinks points at this
        repo's `.config`). Ensures non-zsh sessions (PowerShell, GUI apps)
        resolve XDG lookups to the same location that .zshrc already exports
        for shell sessions.

    .DESCRIPTION
        Writes to HKCU\Environment via [Environment]::SetEnvironmentVariable
        with the "User" scope, which also broadcasts WM_SETTINGCHANGE so newly
        launched processes pick up the value without a logoff. Also sets the
        variable in the current session so steps later in this run see it.
    #>
    Print-Header "Setting XDG_CONFIG_HOME..."

    $target = Join-Path $env:USERPROFILE ".config"
    $current = [Environment]::GetEnvironmentVariable("XDG_CONFIG_HOME", "User")

    if ($current -eq $target) {
        Print-Success "XDG_CONFIG_HOME already set to $target (user scope)."
        $env:XDG_CONFIG_HOME = $target
        return
    }

    if ($DryRun) {
        Print-Warning "`[DRY RUN`] Would set user env XDG_CONFIG_HOME = $target"
        return
    }

    try {
        [Environment]::SetEnvironmentVariable("XDG_CONFIG_HOME", $target, "User")
        $env:XDG_CONFIG_HOME = $target
        Print-Success "XDG_CONFIG_HOME set to $target (user scope)."
    }
    catch {
        Print-Error "Failed to set XDG_CONFIG_HOME: $($_.Exception.Message)"
    }
}

# --- WSL Bridge ---
function Invoke-WslInstall {
    <#
    .SYNOPSIS
        Runs install.sh <subcommand> inside the Ubuntu WSL distro so Linux-side
        dotfiles state (apt, Linuxbrew, stow, zsh) stays in sync with Windows.

    .DESCRIPTION
        Preflights WSL + Ubuntu readiness before attempting. On fresh installs,
        Ubuntu is registered but cannot run commands until the VM Platform
        reboot completes — that case is detected and skipped with a warning.

        We invoke install.sh via the public one-liner (curl | bash) rather than
        a Windows path because install.sh has its own bootstrap that clones
        into the WSL-side $HOME/dotfiles, where stow and Linuxbrew expect it.

    .PARAMETER Subcommand
        'restore' or 'backup' — forwarded as-is to install.sh.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("restore", "backup")]
        [string]$Subcommand
    )

    Print-Header "Running install.sh $Subcommand inside WSL (Ubuntu)..."

    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Print-Warning "wsl command not found. Skipping WSL $Subcommand."
        return
    }

    if ($DryRun) {
        Print-Warning "`[DRY RUN`] Would run inside WSL (Ubuntu): install.sh $Subcommand"
        return
    }

    # Single reliable probe: can we execute inside Ubuntu? This covers both
    # "distro not registered" and "registered but not ready after reboot"
    # in one signal, and avoids parsing `wsl --list` output (UTF-16 LE on
    # many systems even with WSL_UTF8=1).
    wsl -d Ubuntu -- bash -c ":" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Print-Warning "Ubuntu is not reachable (not installed, or reboot pending). Skipping WSL $Subcommand."
        return
    }

    $remoteUrl = "https://raw.githubusercontent.com/rdrkr/dotfiles/main/install.sh"
    $cmd = "curl -fsSL $remoteUrl | bash -s -- $Subcommand"
    try {
        wsl -d Ubuntu -- bash -lc $cmd
        if ($LASTEXITCODE -eq 0) {
            Print-Success "WSL $Subcommand completed."
        }
        else {
            Print-Warning "WSL $Subcommand exited with code $LASTEXITCODE."
        }
    }
    catch {
        Print-Error "WSL $Subcommand failed: $($_.Exception.Message)"
    }
}

# --- Restore ---
function Invoke-Restore {
    <#
    .SYNOPSIS
        Restores dotfiles and installs all dependencies on Windows.
    #>
    Print-Header "Starting Restore... (platform: Windows, pkg managers: winget + scoop)"

    # 0. Enable Developer Mode (best-effort; requires admin)
    Enable-DeveloperMode

    # 1. Check for winget
    Print-Header "Checking for winget..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Print-Success "winget is available."
    }
    else {
        Print-Error "winget not found. Please install App Installer from the Microsoft Store."
        exit 1
    }

    # 2. Install packages from winget-packages.txt
    Print-Header "Installing winget packages..."
    if (Test-Path $WingetPackagesFile) {
        $packages = Get-Content $WingetPackagesFile | Where-Object { $_ -and $_ -notmatch '^\s*#' }
        foreach ($pkg in $packages) {
            $pkg = $pkg.Trim()
            if ($pkg) {
                Run-Command "winget install --id '$pkg' --accept-package-agreements --accept-source-agreements --silent"
            }
        }
        Print-Success "Winget packages installed."
    }
    else {
        Print-Warning "$WingetPackagesFile not found. Skipping."
        Print-Warning "Create it with one winget package ID per line."
    }

    # 3. Install scoop (https://scoop.sh) if missing
    Print-Header "Checking for scoop..."
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Print-Success "scoop is available."
    }
    else {
        Print-Warning "scoop not found. Installing from get.scoop.sh..."
        if (-not $DryRun) {
            try {
                # Scoop refuses to install from an elevated shell by default
                # because it's a per-user package manager. Since this script
                # runs as admin (required for Developer Mode, WSL, etc.),
                # pass -RunAsAdmin to bypass the refusal. Scoop still installs
                # per-user under $env:USERPROFILE\scoop.
                $scoopInstaller = Invoke-RestMethod -Uri "https://get.scoop.sh"
                Invoke-Expression "& { $scoopInstaller } -RunAsAdmin"
                # Refresh PATH so scoop shims are visible in this session
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                Print-Success "scoop installed."
            }
            catch {
                Print-Error "Failed to install scoop: $($_.Exception.Message)"
            }
        }
        else {
            Print-Warning "`[DRY RUN`] Would install scoop via get.scoop.sh -RunAsAdmin"
        }
    }

    # 4. Add scoop buckets from scoop-buckets.txt
    Print-Header "Adding scoop buckets..."
    if (Test-Path $ScoopBucketsFile) {
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            $buckets = Get-Content $ScoopBucketsFile | Where-Object { $_ -and $_ -notmatch '^\s*#' }
            foreach ($bucket in $buckets) {
                $bucket = $bucket.Trim()
                if ($bucket) {
                    Run-Command "scoop bucket add $bucket"
                }
            }
            Print-Success "Scoop buckets added."
        }
        else {
            Print-Warning "scoop not found. Skipping bucket setup."
        }
    }
    else {
        Print-Warning "$ScoopBucketsFile not found. Skipping."
    }

    # 5. Install scoop packages from scoop-packages.txt
    Print-Header "Installing scoop packages..."
    if (Test-Path $ScoopPackagesFile) {
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            $packages = Get-Content $ScoopPackagesFile | Where-Object { $_ -and $_ -notmatch '^\s*#' }
            foreach ($pkg in $packages) {
                $pkg = $pkg.Trim()
                if ($pkg) {
                    Run-Command "scoop install $pkg"
                }
            }
            Print-Success "Scoop packages installed."
        }
        else {
            Print-Warning "scoop not found. Skipping scoop package installation."
        }
    }
    else {
        Print-Warning "$ScoopPackagesFile not found. Skipping."
        Print-Warning "Create it with one scoop package per line (use 'bucket/name' for non-main buckets)."
    }

    # 6. Install Global NPM Packages
    Print-Header "Installing Global NPM Packages..."
    if (Test-Path $NpmGlobalFile) {
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            $packages = Get-Content $NpmGlobalFile | Where-Object { $_ }
            foreach ($pkg in $packages) {
                Run-Command "npm install -g $pkg"
            }
            Print-Success "Global npm packages installed."
        }
        else {
            Print-Warning "npm not found. Skipping npm package installation."
        }
    }
    else {
        Print-Warning "$NpmGlobalFile not found. Skipping."
    }

    # 7. Install Pipx Packages
    Print-Header "Installing Pipx Packages..."
    if (Test-Path $PipxPackagesFile) {
        if (Get-Command pipx -ErrorAction SilentlyContinue) {
            $packages = Get-Content $PipxPackagesFile | Where-Object { $_ }
            foreach ($pkg in $packages) {
                Run-Command "pipx install $pkg"
            }
            Print-Success "Pipx packages installed."
        }
        else {
            Print-Warning "pipx not found. Skipping pipx package installation."
        }
    }
    else {
        Print-Warning "$PipxPackagesFile not found. Skipping."
    }

    # 8. Install Bun Packages
    Print-Header "Installing Bun Packages..."
    if (Test-Path $BunPackagesFile) {
        if (Get-Command bun -ErrorAction SilentlyContinue) {
            $packages = Get-Content $BunPackagesFile | Where-Object { $_ }
            foreach ($pkg in $packages) {
                Run-Command "bun add -g $pkg"
            }
            Print-Success "Bun packages installed."
        }
        else {
            Print-Warning "bun not found. Skipping bun package installation."
        }
    }
    else {
        Print-Warning "$BunPackagesFile not found. Skipping."
    }

    # 9. Install WSL with the latest Ubuntu.
    # Two-phase install. On a fresh Windows box, `wsl --install -d Ubuntu`
    # fails with HCS_E_HYPERV_NOT_INSTALLED because distro registration
    # requires Virtual Machine Platform to be already enabled -- the feature
    # install kicked off in the same command doesn't finalize until reboot.
    # So: if VM Platform or the WSL feature isn't already Enabled, run
    # `wsl --install --no-distribution` (enables features, no distro) and
    # stop; the user reboots and re-runs to land Ubuntu.
    #
    # Detect "Ubuntu is usable" via an execution probe (run `:` inside
    # Ubuntu) rather than parsing `wsl --list --quiet`. The list output is
    # UTF-16 LE on many systems even with $env:WSL_UTF8 set, which breaks
    # string matching; a successful exec proves both "registered" AND
    # "reachable" in one reliable signal.
    Print-Header "Installing WSL (with Ubuntu)..."
    $ubuntuReady = $false
    try {
        wsl -d Ubuntu -- bash -c ":" 2>$null
        if ($LASTEXITCODE -eq 0) { $ubuntuReady = $true }
    }
    catch { }

    $wslFreshInstall = $false
    if ($ubuntuReady) {
        Print-Success "WSL + Ubuntu already installed and ready."
    }
    elseif ($DryRun) {
        Print-Warning "`[DRY RUN`] Would ensure VM Platform + WSL features, then run: wsl --install -d Ubuntu --no-launch"
    }
    else {
        $vmPlatform = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
        $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
        $platformReady = $vmPlatform -and $vmPlatform.State -eq 'Enabled' -and $wslFeature -and $wslFeature.State -eq 'Enabled'

        if (-not $platformReady) {
            Print-Warning "Virtual Machine Platform / WSL feature not enabled. Enabling features (distro install deferred until after reboot)..."
            Run-Command "wsl --install --no-distribution"
            Print-Success "WSL platform features install initiated. Reboot, then re-run this script to finish Ubuntu setup."
            $wslFreshInstall = $true
        }
        else {
            Run-Command "wsl --install -d Ubuntu --no-launch"
            if ($LASTEXITCODE -eq 0) {
                Print-Success "WSL + Ubuntu install initiated."
            }
            else {
                Print-Error "wsl --install -d Ubuntu failed (exit $LASTEXITCODE). Reboot and re-run, or install Ubuntu manually."
            }
            $wslFreshInstall = $true
        }
    }

    # 10. Create symlinks
    Create-Symlinks

    # 10b. Now that %USERPROFILE%\.config exists as a junction, persist
    # XDG_CONFIG_HOME so non-zsh sessions resolve it too.
    Set-XdgConfigHome

    # 10c. Hardlink Windows Terminal settings from the repo into LocalState.
    # Runs after Create-Symlinks (and therefore after winget installs WT)
    # so the package's LocalState folder exists (or is creatable).
    Link-WindowsTerminalSettings

    # 10d. Link PowerShell Profile.
    Link-PowerShellProfile

    # 11. Apply Windows theme + wallpaper
    Apply-WindowsTheme

    # 11b. Restore modern Personalization (accent, dark mode, cursors, etc.)
    # after the theme so its DWM accent overrides theme defaults. Then pin
    # the lock screen via PersonalizationCSP and reapply sign-in programs.
    Restore-WindowsPersonalization
    Apply-WindowsLockScreen
    Restore-WindowsStartup

    # 12. Run install.sh restore inside WSL so Linux-side state (apt, Linuxbrew,
    # stow, zsh) is set up to match. Skip on a fresh install -- the VM Platform
    # feature reboot must complete before Ubuntu can execute commands.
    if ($wslFreshInstall) {
        Print-Header "Skipping WSL install.sh restore (reboot required)"
        Print-Warning "WSL + Ubuntu were just installed. Reboot, then re-run this script to finish the WSL-side setup."
    }
    else {
        Invoke-WslInstall -Subcommand 'restore'
    }

    Write-Host ""
    Write-Host "${C_GREEN}All done! Your dotfiles are set up.${NC}"
    Write-Host ""
}

# --- Backup ---
function Invoke-Backup {
    <#
    .SYNOPSIS
        Backs up the current system state: winget packages, npm/pipx/bun globals,
        and commits changes to git.
    #>
    Print-Header "Starting Backup... (platform: Windows, pkg managers: winget + scoop)"

    # Backup winget packages.
    # Use `winget export --source winget` so the file only contains packages
    # the `winget` source can actually install. Plain `winget list` also shows
    # MSIX/ARP entries (Microsoft Store, classic installers), which break
    # `winget install --id` on restore.
    Print-Header "Backing up winget packages..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if (-not $DryRun) {
            $tempJson = [System.IO.Path]::GetTempFileName()
            try {
                winget export --output $tempJson --source winget --accept-source-agreements | Out-Null
                if (Test-Path $tempJson) {
                    $data = Get-Content $tempJson -Raw -Encoding UTF8 | ConvertFrom-Json
                    $ids = @()
                    foreach ($src in $data.Sources) {
                        foreach ($pkg in $src.Packages) { $ids += $pkg.PackageIdentifier }
                    }
                    $ids | Where-Object { $_ } | Sort-Object -Unique |
                        Out-File -FilePath $WingetPackagesFile -Encoding utf8
                    Print-Success "Winget packages backed up to $WingetPackagesFile."
                }
                else {
                    Print-Warning "winget export produced no output. Skipping."
                }
            }
            finally {
                if (Test-Path $tempJson) { Remove-Item $tempJson -Force -ErrorAction SilentlyContinue }
            }
        }
        else {
            Print-Warning "`[DRY RUN`] Would backup winget packages to $WingetPackagesFile"
        }
    }
    else {
        Print-Warning "winget not found. Skipping."
    }

    # Backup scoop buckets.
    Print-Header "Backing up scoop buckets..."
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        if (-not $DryRun) {
            scoop bucket list | ForEach-Object { $_.Name } |
                Where-Object { $_ } | Sort-Object -Unique |
                Out-File -FilePath $ScoopBucketsFile -Encoding utf8
            Print-Success "Scoop buckets backed up to $ScoopBucketsFile."
        }
        else {
            Print-Warning "`[DRY RUN`] Would backup scoop buckets to $ScoopBucketsFile"
        }
    }
    else {
        Print-Warning "scoop not found. Skipping scoop bucket backup."
    }

    # Backup scoop packages.
    # For packages from non-default buckets, prefix with `bucket/` so restore
    # can resolve them without relying on bucket resolution order.
    Print-Header "Backing up scoop packages..."
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        if (-not $DryRun) {
            scoop list | ForEach-Object {
                if (-not $_.Source -or $_.Source -eq 'main') { $_.Name }
                else { "$($_.Source)/$($_.Name)" }
            } | Where-Object { $_ } | Sort-Object -Unique |
                Out-File -FilePath $ScoopPackagesFile -Encoding utf8
            Print-Success "Scoop packages backed up to $ScoopPackagesFile."
        }
        else {
            Print-Warning "`[DRY RUN`] Would backup scoop packages to $ScoopPackagesFile"
        }
    }
    else {
        Print-Warning "scoop not found. Skipping scoop package backup."
    }

    # Backup Global NPM Packages
    Print-Header "Backing up Global NPM Packages..."
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        if (-not $DryRun) {
            $npmPackages = npm list -g --depth=0 --parseable 2>$null |
            ForEach-Object {
                if ($_ -match 'node_modules[\\/](.+)$') {
                    $matches[1] -replace '\\', '/'
                }
            } | Where-Object { $_ -notin @("npm", "corepack") }
            $npmPackages | Out-File -FilePath $NpmGlobalFile -Encoding utf8
            Print-Success "Global npm packages backed up to $NpmGlobalFile."
        }
        else {
            Print-Warning "`[DRY RUN`] Would backup global npm packages to $NpmGlobalFile"
        }
    }
    else {
        Print-Warning "npm not found. Skipping npm backup."
    }

    # Backup Pipx Packages
    Print-Header "Backing up Pipx Packages..."
    if (Get-Command pipx -ErrorAction SilentlyContinue) {
        if (-not $DryRun) {
            pipx list --short | ForEach-Object { ($_ -split ' ')[0] } | Out-File -FilePath $PipxPackagesFile -Encoding utf8
            Print-Success "Pipx packages backed up to $PipxPackagesFile."
        }
        else {
            Print-Warning "`[DRY RUN`] Would backup pipx packages to $PipxPackagesFile"
        }
    }
    else {
        Print-Warning "pipx not found. Skipping pipx backup."
    }

    # Backup Bun Packages
    Print-Header "Backing up Bun Packages..."
    if (Get-Command bun -ErrorAction SilentlyContinue) {
        if (-not $DryRun) {
            bun pm ls -g | Where-Object { $_ -notmatch 'node_modules' } |
            ForEach-Object { ($_ -split ' ')[1] -replace '@[^@]*$', '' } |
            Out-File -FilePath $BunPackagesFile -Encoding utf8
            Print-Success "Bun packages backed up to $BunPackagesFile."
        }
        else {
            Print-Warning "`[DRY RUN`] Would backup bun packages to $BunPackagesFile"
        }
    }
    else {
        Print-Warning "bun not found. Skipping bun backup."
    }

    # Backup modern Personalization settings, lock screen image, startup
    # programs, and Windows Terminal settings before any symlinks/commits
    # so the new files land in the working tree and are picked up by
    # Create-Symlinks + the final git commit.
    Backup-WindowsLockScreen
    Backup-WindowsPersonalization
    Backup-WindowsStartup
    Backup-WindowsTerminalSettings

    Create-Symlinks

    # Run install.sh backup inside WSL before committing from Windows.
    # The WSL-side backup may produce its own commit+push in the cloned Linux
    # repo; the Windows `git pull --rebase` below picks that up.
    Invoke-WslInstall -Subcommand 'backup'

    if (-not $DryRun) {
        $status = git -C $ScriptDir status --porcelain
        if ($status) {
            Print-Warning "Changes detected. Committing and pushing..."
            Run-Command "git -C '$ScriptDir' add ."
            Run-Command "git -C '$ScriptDir' commit -m 'chore(backup): automated backup of dotfiles changes'"
            Run-Command "git -C '$ScriptDir' pull origin main --rebase"
            Run-Command "git -C '$ScriptDir' push origin main"
            Print-Success "Changes committed and pushed."
        }
        else {
            Print-Success "No changes detected. Nothing to commit."
        }
    }
}

# --- Schedule ---
function Invoke-Schedule {
    <#
    .SYNOPSIS
        Registers a Windows Task Scheduler task that runs backup hourly.
    #>
    Print-Header "Scheduling Hourly Backups (Task Scheduler)..."

    $taskName = "DotfilesBackup"
    $scriptPath = Join-Path $ScriptDir "install.ps1"

    if ($DryRun) {
        $exe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell.exe" }
        Print-Warning "`[DRY RUN`] Would create scheduled task '$taskName' running hourly."
        Print-Warning "`[DRY RUN`] Command: $exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" backup"
        return
    }

    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Print-Success "Scheduled task '$taskName' already exists."
    }
    else {
        $exe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell.exe" }
        # Use -File for consistency and to avoid ampersand parser errors in scheduled tasks.
        $action = New-ScheduledTaskAction -Execute "$exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" backup"
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Hourly dotfiles backup" | Out-Null
        if ($?) {
            Print-Success "Backup scheduled to run hourly via Task Scheduler."
        }
        else {
            Print-Error "Failed to create scheduled task."
            exit 1
        }
    }
}

# --- Main ---
if ($Help -or $Command -eq "help") {
    Print-Help
    exit 0
}

if (-not $Command) {
    Print-Error "No command specified."
    Print-Help
    exit 1
}

if ($DryRun) {
    Print-Warning "Running in dry-run mode. No changes will be made."
}

# Only print logo if not bootstrapping (it will be printed by the local script)
if (Test-IsLocal) {
    Print-Logo
    Print-Success "Detected platform: Windows (winget + scoop)"
    Write-Host ""
}

try {
    switch ($Command) {
        "restore" { Invoke-Restore }
        "backup" { Invoke-Backup }
        "schedule" { Invoke-Schedule }
    }
}
catch {
    Print-Error "Unhandled error: $($_.Exception.Message)"
    if ($_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace
    }
    exit 1
}
