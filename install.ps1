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
$ValidCommands = @("restore", "backup", "schedule", "help")
if ($Command -and $Command -notin $ValidCommands) {
    Write-Host "`e[38;2;250;179;135m✗ Invalid command: $Command. Valid commands are: $($ValidCommands -join ', ')`e[0m"
    exit 1
}
$DotfilesDir = Join-Path $env:USERPROFILE "dotfiles"
$DotfilesRepo = "https://github.com/rdrkr/dotfiles.git"

# --- Bootstrap ---
# When invoked remotely (irm ... | iex), $MyInvocation.MyCommand.Definition
# will not point to a file inside the repo. Detect this and bootstrap.
function Test-IsLocal {
    $scriptPath = $MyInvocation.ScriptName
    if (-not $scriptPath) { return $false }
    $parentDir = Split-Path -Parent $scriptPath
    return (Test-Path (Join-Path $parentDir ".git"))
}

function Invoke-Bootstrap {
    <#
    .SYNOPSIS
        Installs git via winget, clones the repo, and re-executes locally.
    #>
    Write-Host "`e[38;2;137;180;250m=== Bootstrapping dotfiles ===`e[0m"

    # Ensure winget is available
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "`e[38;2;250;179;135m✗ winget not found. Please install App Installer from the Microsoft Store.`e[0m"
        exit 1
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
    }
    else {
        Write-Host "Cloning dotfiles repo..."
        git clone $DotfilesRepo $DotfilesDir
    }

    # Re-execute from the cloned repo
    Write-Host "Handing off to local install.ps1..."
    $localScript = Join-Path $DotfilesDir "install.ps1"
    if ($Command) {
        & $localScript $Command
    }
    else {
        & $localScript restore
    }
    exit $LASTEXITCODE
}

if (-not (Test-IsLocal)) {
    Invoke-Bootstrap
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$WingetPackagesFile = Join-Path $ScriptDir ".config\winget-packages.txt"
$NpmGlobalFile = Join-Path $ScriptDir ".config\npm-global-packages.txt"
$PipxPackagesFile = Join-Path $ScriptDir ".config\pipx-packages.txt"
$BunPackagesFile = Join-Path $ScriptDir ".config\bun-packages.txt"
$DotfilesTarget = $env:USERPROFILE

# --- Colors (ANSI escape sequences) ---
$NC = "`e[0m"
$C_LAVENDER = "`e[38;2;180;190;254m"
$C_BLUE = "`e[38;2;137;180;250m"
$C_SAPPHIRE = "`e[38;2;116;199;236m"
$C_SKY = "`e[38;2;137;220;235m"
$C_TEAL = "`e[38;2;148;226;213m"
$C_GREEN = "`e[38;2;166;227;161m"
$C_YELLOW = "`e[38;2;249;226;175m"
$C_PEACH = "`e[38;2;250;179;135m"

# --- Logo ---
function Print-Logo {
    Write-Host "${C_LAVENDER}██████╗   ██████╗  ████████╗ ███████╗ ██╗ ██╗      ███████╗ ███████╗${NC}"
    Write-Host "${C_BLUE}██╔══██╗ ██╔═══██╗ ╚══██╔══╝ ██╔════╝ ██║ ██║      ██╔════╝ ██╔════╝${NC}"
    Write-Host "${C_SAPPHIRE}██║  ██║ ██║   ██║    ██║    █████╗   ██║ ██║      █████╗   ███████╗${NC}"
    Write-Host "${C_SKY}██║  ██║ ██║   ██║    ██║    ██╔══╝   ██║ ██║      ██╔════╝ ╚════██║${NC}"
    Write-Host "${C_TEAL}██████╔╝ ╚██████╔╝    ██║    ██║      ██║ ███████╗ ███████║ ███████║${NC}"
    Write-Host "${C_GREEN}╚═════╝   ╚═════╝     ╚═╝    ╚═╝      ╚═╝ ╚══════╝ ╚══════╝ ╚══════╝${NC}"
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
    Write-Host "${C_GREEN}✓ $Message${NC}"
}

function Print-Warning {
    param([string]$Message)
    Write-Host "${C_YELLOW}⚠ $Message${NC}"
}

function Print-Error {
    param([string]$Message)
    Write-Host "${C_PEACH}✗ $Message${NC}"
}

function Print-Help {
    Print-Logo
    Write-Host "Usage: .\install.ps1 <command> [options]"
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
        Write-Host "${C_YELLOW}[DRY RUN] Would execute: $Cmd${NC}"
    }
    else {
        Invoke-Expression $Cmd
    }
}

# --- Symlink Creation (stow alternative) ---
function Create-Symlinks {
    <#
    .SYNOPSIS
        Creates symlinks from the dotfiles directory into the user's home,
        mirroring what GNU Stow does on Unix systems.
    #>
    Print-Header "Creating symlinks..."

    # Directories to symlink into $HOME (mirrors stow behavior)
    $configSource = Join-Path $ScriptDir ".config"
    $configTarget = Join-Path $DotfilesTarget ".config"

    if (Test-Path $configSource) {
        $items = Get-ChildItem -Path $configSource -Directory
        foreach ($item in $items) {
            $target = Join-Path $configTarget $item.Name
            if (Test-Path $target) {
                Print-Warning "Already exists, skipping: $target"
            }
            else {
                if (-not $DryRun) {
                    if (-not (Test-Path $configTarget)) {
                        New-Item -ItemType Directory -Path $configTarget -Force | Out-Null
                    }
                    New-Item -ItemType SymbolicLink -Path $target -Target $item.FullName -Force | Out-Null
                    Print-Success "Linked: $($item.FullName) -> $target"
                }
                else {
                    Print-Warning "[DRY RUN] Would link: $($item.FullName) -> $target"
                }
            }
        }
    }

    # Symlink individual dotfiles from repo root (e.g., .zshrc, .gitconfig)
    $dotfiles = Get-ChildItem -Path $ScriptDir -File -Filter ".*" | Where-Object {
        $_.Name -notin @(".git", ".gitignore", ".gitmodules", ".DS_Store")
    }
    foreach ($file in $dotfiles) {
        $target = Join-Path $DotfilesTarget $file.Name
        if (Test-Path $target) {
            Print-Warning "Already exists, skipping: $target"
        }
        else {
            if (-not $DryRun) {
                New-Item -ItemType SymbolicLink -Path $target -Target $file.FullName -Force | Out-Null
                Print-Success "Linked: $($file.FullName) -> $target"
            }
            else {
                Print-Warning "[DRY RUN] Would link: $($file.FullName) -> $target"
            }
        }
    }

    Print-Success "Symlink creation completed."
}

# --- Restore ---
function Invoke-Restore {
    <#
    .SYNOPSIS
        Restores dotfiles and installs all dependencies on Windows.
    #>
    Print-Header "Starting Restore... (platform: Windows, pkg manager: winget)"

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

    # 3. Install Global NPM Packages
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

    # 4. Install Pipx Packages
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

    # 5. Install Bun Packages
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

    # 6. Create symlinks
    Create-Symlinks

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
    Print-Header "Starting Backup... (platform: Windows, pkg manager: winget)"

    # Backup winget packages
    Print-Header "Backing up winget packages..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if (-not $DryRun) {
            winget list | Select-Object -Skip 2 | ForEach-Object {
                ($_ -split '\s{2,}')[1]
            } | Where-Object { $_ } | Sort-Object > $WingetPackagesFile
            Print-Success "Winget packages backed up to $WingetPackagesFile."
        }
        else {
            Print-Warning "[DRY RUN] Would backup winget packages to $WingetPackagesFile"
        }
    }
    else {
        Print-Warning "winget not found. Skipping."
    }

    # Backup Global NPM Packages
    Print-Header "Backing up Global NPM Packages..."
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        if (-not $DryRun) {
            $npmPackages = npm list -g --depth=0 --parseable 2>$null |
            Split-Path -Leaf |
            Where-Object { $_ -notin @("npm", "corepack", "lib", "node_modules") }
            $npmPackages | Out-File -FilePath $NpmGlobalFile -Encoding utf8
            Print-Success "Global npm packages backed up to $NpmGlobalFile."
        }
        else {
            Print-Warning "[DRY RUN] Would backup global npm packages to $NpmGlobalFile"
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
            Print-Warning "[DRY RUN] Would backup pipx packages to $PipxPackagesFile"
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
            Print-Warning "[DRY RUN] Would backup bun packages to $BunPackagesFile"
        }
    }
    else {
        Print-Warning "bun not found. Skipping bun backup."
    }

    Create-Symlinks

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
        Print-Warning "[DRY RUN] Would create scheduled task '$taskName' running hourly."
        Print-Warning "[DRY RUN] Command: pwsh -NoProfile -File `"$scriptPath`" backup"
        return
    }

    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Print-Success "Scheduled task '$taskName' already exists."
    }
    else {
        $action = New-ScheduledTaskAction -Execute "pwsh" -Argument "-NoProfile -File `"$scriptPath`" backup"
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

Print-Logo
Print-Success "Detected platform: Windows (winget)"
Write-Host ""

switch ($Command) {
    "restore" { Invoke-Restore }
    "backup" { Invoke-Backup }
    "schedule" { Invoke-Schedule }
}
