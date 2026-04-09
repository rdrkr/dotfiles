# ✨ Dotfiles

My personal dotfiles, managed with `stow` (macOS/Linux) and PowerShell symlinks (Windows).

## 🖥️ Supported Platforms

| Platform | Script | Package Manager |
|----------|--------|-----------------|
| macOS | `install.sh` | Homebrew |
| Ubuntu / Debian | `install.sh` | apt + Linuxbrew |
| Fedora / RHEL | `install.sh` | dnf + Linuxbrew |
| Arch Linux | `install.sh` | pacman + Linuxbrew |
| openSUSE | `install.sh` | zypper + Linuxbrew |
| WSL | `install.sh` | (distro PM + Linuxbrew) |
| Windows (native) | `install.ps1` | winget |

## 🚀 Installation

One command to set up everything. The script automatically installs prerequisites (Xcode CLI tools, Homebrew, git, etc.), clones the repo, and runs a full restore.

### macOS / Linux / WSL

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rdrkr/dotfiles/main/install.sh)
```

### Windows (native)

Run as Administrator in PowerShell:

```powershell
irm https://raw.githubusercontent.com/rdrkr/dotfiles/main/install.ps1 | iex
```

> The scripts detect your platform, install any missing prerequisites, clone the repo to `~/dotfiles`, and run `restore`.

## 🛠️ Usage

### Restore

Restore dotfiles and install all dependencies:

```bash
# macOS / Linux / WSL
./install.sh restore

# Windows
.\install.ps1 restore
```

### Backup

Update package lists with the current setup and commit changes:

```bash
# macOS / Linux / WSL
./install.sh backup

# Windows
.\install.ps1 backup
```

### Schedule

Schedule hourly automated backups:

```bash
# macOS / Linux / WSL (cron)
./install.sh schedule

# Windows (Task Scheduler)
.\install.ps1 schedule
```

### Dry Run

Preview what would happen without making changes:

```bash
# macOS / Linux / WSL
./install.sh restore --dry-run

# Windows
.\install.ps1 restore -DryRun
```

## 📁 Package List Files

| File | Purpose |
|------|---------|
| `.config/Brewfile` | Homebrew packages (macOS) |
| `.config/apt-packages.txt` | apt packages (Debian/Ubuntu) |
| `.config/dnf-packages.txt` | dnf packages (Fedora/RHEL) |
| `.config/pacman-packages.txt` | pacman packages (Arch) |
| `.config/zypper-packages.txt` | zypper packages (openSUSE) |
| `.config/winget-packages.txt` | winget packages (Windows) |
| `.config/npm-global-packages.txt` | Global npm packages (all platforms) |
| `.config/pipx-packages.txt` | Pipx packages (all platforms) |
| `.config/bun-packages.txt` | Bun packages (all platforms) |

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
