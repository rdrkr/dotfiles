#!/bin/bash

# --- Configuration ---
DOTFILES_DIR="${HOME}/dotfiles"
DOTFILES_REPO="https://github.com/rdrkr/dotfiles.git"
DRY_RUN=false

# --- Bootstrap ---
# When the script is executed remotely (e.g. curl | bash), BASH_SOURCE[0]
# resolves to stdin rather than a file inside the cloned repo. In that case
# we install the bare-minimum prerequisites, clone the repo, and re-execute
# the local copy so that Brewfile, package lists, and configs are available.
is_local() {
  local src="${BASH_SOURCE[0]}"
  [ -n "$src" ] && [ "$src" != "/dev/stdin" ] && [ -d "$(dirname "$src")/.git" ]
}

bootstrap() {
  echo -e "\033[38;2;137;180;250m=== Bootstrapping dotfiles ===\033[0m"

  case "$(uname -s)" in
  Darwin)
    # Xcode Command Line Tools
    if ! xcode-select -p &>/dev/null; then
      echo "Installing Xcode Command Line Tools..."
      xcode-select --install
      echo "Waiting for Xcode Command Line Tools installation..."
      until xcode-select -p &>/dev/null; do sleep 5; done
    fi
    # Homebrew
    if ! command -v brew &>/dev/null; then
      echo "Installing Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      # Add brew to PATH for the rest of this session
      if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    fi
    # Git (via Homebrew)
    if ! command -v git &>/dev/null; then
      brew install git
    fi
    ;;
  Linux)
    if ! command -v git &>/dev/null; then
      echo "Installing git..."
      if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y git
      elif command -v dnf &>/dev/null; then
        sudo dnf install -y git
      elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm git
      elif command -v zypper &>/dev/null; then
        sudo zypper install -y git
      else
        echo "Error: no supported package manager found. Install git manually."
        exit 1
      fi
    fi
    ;;
  *)
    echo "Error: unsupported OS."
    exit 1
    ;;
  esac

  # Clone the repo (or pull if it already exists)
  if [ -d "$DOTFILES_DIR/.git" ]; then
    echo "Dotfiles repo already exists. Pulling latest changes..."
    git -C "$DOTFILES_DIR" pull origin main
  else
    echo "Cloning dotfiles repo..."
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  fi

  # Re-execute from the cloned repo, forwarding any arguments
  echo "Handing off to local install.sh..."
  exec "$DOTFILES_DIR/install.sh" "$@"
}

# If running remotely, bootstrap first and exit (exec replaces the process)
if ! is_local; then
  # Default to restore when invoked via the one-liner with no arguments
  if [ $# -eq 0 ]; then
    bootstrap restore
  else
    bootstrap "$@"
  fi
fi

# --- Go to dotfiles repo directory ---
# Store the original directory and change to the script's directory.
# This allows the script to be run from any location.
ORIGINAL_DIR=$(pwd)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "$SCRIPT_DIR" || exit
# Restore the original directory when the script exits.
trap 'cd "$ORIGINAL_DIR"' EXIT

NPM_GLOBAL_FILE="${SCRIPT_DIR}/.config/npm-global-packages.txt"
PIPX_PACKAGES_FILE="${SCRIPT_DIR}/.config/pipx-packages.txt"
BUN_PACKAGES_FILE="${SCRIPT_DIR}/.config/bun-packages.txt"

# --- Colors ---
NC="\033[0m" # No Color

# Catppuccin Mocha Colors
C_LAVENDER="\033[38;2;180;190;254m"
C_BLUE="\033[38;2;137;180;250m"
C_SAPPHIRE="\033[38;2;116;199;236m"
C_SKY="\033[38;2;137;220;235m"
C_TEAL="\033[38;2;148;226;213m"
C_GREEN="\033[38;2;166;227;161m"
C_YELLOW="\033[38;2;249;226;175m"
C_PEACH="\033[38;2;250;179;135m"

# --- Logo ---
print_logo() {
  echo -e "${C_LAVENDER}"
  echo -n "██████╗   ██████╗  ████████╗ ███████╗ ██╗ ██╗      ███████╗ ███████╗"
  echo -e "${C_BLUE}"
  echo -n "██╔══██╗ ██╔═══██╗ ╚══██╔══╝ ██╔════╝ ██║ ██║      ██╔════╝ ██╔════╝"
  echo -e "${C_SAPPHIRE}"
  echo -n "██║  ██║ ██║   ██║    ██║    █████╗   ██║ ██║      █████╗   ███████╗"
  echo -e "${C_SKY}"
  echo -n "██║  ██║ ██║   ██║    ██║    ██╔══╝   ██║ ██║      ██╔════╝ ╚════██║"
  echo -e "${C_TEAL}"
  echo -n "██████╔╝ ╚██████╔╝    ██║    ██║      ██║ ███████╗ ███████║ ███████║"
  echo -e "${C_GREEN}"
  echo -n "╚═════╝   ╚═════╝     ╚═╝    ╚═╝      ╚═╝ ╚══════╝ ╚══════╝ ╚══════╝"
  echo -e "${NC}"
  echo
}

# --- Functions ---
print_header() {
  echo -e "${C_BLUE}=================================================${NC}"
  echo -e "${C_LAVENDER} $1 ${NC}"
  echo -e "${C_BLUE}=================================================${NC}"
}

print_success() {
  echo -e "${C_GREEN}✓ $1${NC}"
}

print_warning() {
  echo -e "${C_YELLOW}⚠ $1${NC}"
}

print_error() {
  echo -e "${C_PEACH}✗ $1${NC}"
}

print_help() {
  print_logo
  echo "Usage: ./install.sh <command> [options]"
  echo ""
  echo "Commands:"
  echo "  restore      Restore dotfiles and install dependencies"
  echo "  backup       Update package lists with current setup"
  echo "  schedule     Schedule hourly backups using cron"
  echo ""
  echo "Options:"
  echo "  -h, --help     Show this help message and exit"
  echo "  -d, --dry-run  Run the script in dry-run mode (no changes will be made)"
  echo ""
  echo "Supported platforms: macOS, Linux (apt, dnf, pacman, zypper), WSL"
}

run_command() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${C_YELLOW}[DRY RUN] Would execute: $1${NC}"
  else
    eval "$1"
  fi
}

# --- Platform Detection ---
# Detects the current operating system and sets OS_TYPE, IS_WSL, and DISTRO_ID.
detect_platform() {
  OS_TYPE="unknown"
  IS_WSL=false
  DISTRO_ID="unknown"

  case "$(uname -s)" in
  Darwin)
    OS_TYPE="macos"
    ;;
  Linux)
    OS_TYPE="linux"
    if grep -qi microsoft /proc/version 2>/dev/null; then
      IS_WSL=true
    fi
    if [ -f /etc/os-release ]; then
      DISTRO_ID=$(. /etc/os-release && echo "$ID")
    fi
    ;;
  *)
    print_error "Unsupported operating system: $(uname -s)"
    exit 1
    ;;
  esac
}

# --- Package Manager Abstraction ---
# Detects the system package manager and sets PKG_MANAGER, along with
# PKG_INSTALL, PKG_UPDATE, and PKG_LIST_FILE for use in restore/backup.
detect_package_manager() {
  PKG_MANAGER="unknown"
  PKG_INSTALL=""
  PKG_UPDATE=""
  PKG_LIST_FILE=""

  if [ "$OS_TYPE" = "macos" ]; then
    PKG_MANAGER="brew"
    PKG_INSTALL="brew install"
    PKG_UPDATE="brew update"
    PKG_LIST_FILE="${SCRIPT_DIR}/.config/Brewfile"
  elif [ "$OS_TYPE" = "linux" ]; then
    if command -v apt-get &>/dev/null; then
      PKG_MANAGER="apt"
      PKG_INSTALL="sudo apt-get install -y"
      PKG_UPDATE="sudo apt-get update"
      PKG_LIST_FILE="${SCRIPT_DIR}/.config/apt-packages.txt"
    elif command -v dnf &>/dev/null; then
      PKG_MANAGER="dnf"
      PKG_INSTALL="sudo dnf install -y"
      PKG_UPDATE="sudo dnf check-update || true"
      PKG_LIST_FILE="${SCRIPT_DIR}/.config/dnf-packages.txt"
    elif command -v pacman &>/dev/null; then
      PKG_MANAGER="pacman"
      PKG_INSTALL="sudo pacman -S --noconfirm"
      PKG_UPDATE="sudo pacman -Sy"
      PKG_LIST_FILE="${SCRIPT_DIR}/.config/pacman-packages.txt"
    elif command -v zypper &>/dev/null; then
      PKG_MANAGER="zypper"
      PKG_INSTALL="sudo zypper install -y"
      PKG_UPDATE="sudo zypper refresh"
      PKG_LIST_FILE="${SCRIPT_DIR}/.config/zypper-packages.txt"
    else
      print_error "No supported package manager found (apt, dnf, pacman, zypper)."
      exit 1
    fi
  fi
}

# --- Stow ---
# Runs GNU Stow to symlink dotfiles into the home directory.
# Uses --adopt to handle pre-existing files: stow moves them into the repo,
# then git checkout restores the repo's canonical versions.
run_stow() {
  local mode="${1:-restore}"
  print_header "Running stow..."
  if command -v stow &>/dev/null; then
    run_command "stow --adopt ."
    if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
      print_error "Stow command failed."
      exit 1
    fi
    # During restore, discard adopted files so symlinks point to repo versions.
    # During backup, keep adopted files — they represent the current state we want to commit.
    if [ "$mode" = "restore" ] && [ "$DRY_RUN" = false ]; then
      run_command "git -C \"$SCRIPT_DIR\" checkout ."
    fi
    print_success "Stow command completed successfully."
  else
    print_error "Stow is not installed. Please install it first."
    exit 1
  fi
}

# --- Install System Packages ---
# Installs system packages from the appropriate package list for the detected platform.
install_system_packages() {
  if [ "$OS_TYPE" = "macos" ]; then
    install_macos_packages
  elif [ "$OS_TYPE" = "linux" ]; then
    install_linux_packages
  fi
}

# --- macOS Package Installation ---
# Installs Homebrew if needed, then runs brew bundle from the Brewfile.
install_macos_packages() {
  print_header "Checking for Homebrew..."
  if ! command -v brew &>/dev/null; then
    print_warning "Installing Xcode Command Line Tools..."
    xcode-select --install || true

    print_warning "Homebrew not found. Installing..."
    run_command '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
      print_error "Homebrew installation failed."
      exit 1
    fi
    print_success "Homebrew installed successfully."
  else
    print_success "Homebrew is already installed."
  fi

  print_header "Installing from Brewfile..."
  if [ -f ".config/Brewfile" ]; then
    if [ "$DRY_RUN" = false ]; then
      read -p "Are you logged into the App Store? (y/n) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Please log in to the App Store to continue."
        run_command "open -a 'App Store'"
        exit 1
      fi
    fi
    run_command "brew bundle --file=.config/Brewfile"
    if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
      print_error "Brew bundle command failed."
      exit 1
    fi
    print_success "Brewfile dependencies installed."
  else
    print_warning "Brewfile not found. Skipping brew bundle."
  fi
}

# --- Linux Package Installation ---
# Installs native distro packages, then Linuxbrew and Brewfile packages.
install_linux_packages() {
  print_header "Updating package index ($PKG_MANAGER)..."
  run_command "$PKG_UPDATE"

  print_header "Installing system packages ($PKG_MANAGER)..."
  if [ -f "$PKG_LIST_FILE" ]; then
    # Build the exclude set: apt-specific exclusions for WSL (GUI/boot/kernel
    # packages that don't belong in a Windows-hosted Linux distro).
    local -A excluded=()
    if [ "$PKG_MANAGER" = "apt" ] && [ "$IS_WSL" = true ]; then
      local exclude_file="${SCRIPT_DIR}/.config/apt-exclude-windows.txt"
      if [ -f "$exclude_file" ]; then
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          [ "${line:0:1}" = "#" ] && continue
          excluded["$line"]=1
        done <"$exclude_file"
      fi
    fi

    if [ "$DRY_RUN" = false ]; then
      local packages=""
      while IFS= read -r package; do
        [ -z "$package" ] && continue
        [ "${package:0:1}" = "#" ] && continue
        [ -n "${excluded[$package]:-}" ] && continue
        packages="$packages $package"
      done <"$PKG_LIST_FILE"
      if [ -n "$packages" ]; then
        run_command "$PKG_INSTALL $packages"
        if [ $? -ne 0 ]; then
          print_error "Package installation failed."
          exit 1
        fi
      fi
    else
      print_warning "[DRY RUN] Would install packages from $PKG_LIST_FILE"
    fi
    print_success "System packages installed."
  else
    print_warning "$PKG_LIST_FILE not found. Skipping system package installation."
    print_warning "Create $PKG_LIST_FILE with one package name per line."
  fi

  # Ensure stow is installed on Linux
  if ! command -v stow &>/dev/null; then
    print_header "Installing stow..."
    run_command "$PKG_INSTALL stow"
  fi

  # Install zsh and set it as the default shell
  install_zsh

  # Install Linuxbrew and Brewfile packages
  install_linuxbrew
}

# --- Zsh Installation ---
# Installs zsh via the native package manager and sets it as the default login shell.
install_zsh() {
  if command -v zsh &>/dev/null; then
    print_success "zsh is already installed."
  else
    print_header "Installing zsh..."
    run_command "$PKG_INSTALL zsh"
    if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
      print_error "Failed to install zsh."
      return 1
    fi
    print_success "zsh installed."
  fi

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would ensure zsh is the default login shell."
    return 0
  fi

  # Use the real login shell from /etc/passwd, not $SHELL (which just reflects
  # the shell that invoked this script).
  local zsh_path login_shell
  zsh_path="$(command -v zsh)"
  login_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
  if [ "$login_shell" = "$zsh_path" ]; then
    print_success "zsh is already the default shell."
    return 0
  fi

  # Ensure zsh is listed in /etc/shells so chsh accepts it.
  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    print_warning "Adding $zsh_path to /etc/shells..."
    run_command "echo '$zsh_path' | sudo tee -a /etc/shells >/dev/null"
  fi
  print_warning "Changing default shell to zsh..."
  run_command "sudo chsh -s '$zsh_path' '$USER'"
  if [ $? -eq 0 ]; then
    print_success "Default shell changed to zsh. Log out and back in for it to take effect."
  else
    print_error "Failed to change default shell. You can run: chsh -s $zsh_path"
  fi
}

# --- Linuxbrew Installation ---
# Installs Homebrew on Linux and runs brew bundle from the Brewfile.
# This provides the same CLI toolset available on macOS.
install_linuxbrew() {
  print_header "Checking for Linuxbrew..."
  if ! command -v brew &>/dev/null; then
    # Linuxbrew requires build-essential/gcc and curl
    case "$PKG_MANAGER" in
    apt)    run_command "sudo apt-get install -y build-essential curl" ;;
    dnf)    run_command "sudo dnf groupinstall -y 'Development Tools' && sudo dnf install -y curl" ;;
    pacman) run_command "sudo pacman -S --noconfirm --needed base-devel curl" ;;
    zypper) run_command "sudo zypper install -y -t pattern devel_basis && sudo zypper install -y curl" ;;
    esac

    print_warning "Installing Linuxbrew..."
    run_command 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
      print_error "Linuxbrew installation failed."
      return 1
    fi
    # Add brew to PATH for the rest of this session
    if [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
    print_success "Linuxbrew installed successfully."

    # Install GCC as recommended by Homebrew on Linux
    print_header "Installing GCC (recommended by Linuxbrew)..."
    run_command "brew install gcc"
  else
    print_success "Linuxbrew is already installed."
  fi

  print_header "Installing from Brewfile (Linuxbrew)..."
  if [ -f ".config/Brewfile" ]; then
    # Filter out packages that don't apply on Linux (always) and, when running
    # inside WSL on Windows, additional packages provided by Docker Desktop.
    # Each exclude file contains one bare package name per line. We strip
    # matching `"<name>"` occurrences via fixed-string grep.
    local linux_brewfile
    linux_brewfile=$(mktemp)
    cp ".config/Brewfile" "$linux_brewfile"

    local exclude_files=("${SCRIPT_DIR}/.config/brew-exclude-linux.txt")
    if [ "$IS_WSL" = true ]; then
      exclude_files+=("${SCRIPT_DIR}/.config/brew-exclude-windows.txt")
    fi

    for ef in "${exclude_files[@]}"; do
      [ -f "$ef" ] || continue
      while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        [ "${pkg:0:1}" = "#" ] && continue
        local filtered
        filtered=$(mktemp)
        grep -vF "\"$pkg\"" "$linux_brewfile" >"$filtered" || true
        mv "$filtered" "$linux_brewfile"
      done <"$ef"
    done

    run_command "brew bundle --file=$linux_brewfile"
    if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
      print_warning "Some Brewfile entries may have failed (platform-specific packages are expected to skip)."
    fi
    rm -f "$linux_brewfile"
    print_success "Brewfile dependencies installed."
  else
    print_warning "Brewfile not found. Skipping brew bundle."
  fi
}

# --- Restore ---
# Restores dotfiles and installs all dependencies for the detected platform.
restore() {
  print_header "Starting Restore... (platform: ${OS_TYPE}, pkg manager: ${PKG_MANAGER})"

  # 1. Install system packages
  install_system_packages

  # 2. macOS-only: Setup default applications with infat
  if [ "$OS_TYPE" = "macos" ]; then
    print_header "Setting up default macOS applications..."
    run_command "source \"${HOME}/.zshrc\""
    if command -v infat &>/dev/null; then
      run_command "infat --config ~/.config/infat/config.toml"
      if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
        print_error "infat command failed."
        exit 1
      fi
      print_success "Default macOS applications configured."
    else
      print_warning "infat not found. Skipping default application setup."
    fi
  fi

  # 3. Install Global NPM Packages
  print_header "Installing Global NPM Packages..."
  if [ -f "$NPM_GLOBAL_FILE" ]; then
    if command -v npm &>/dev/null; then
      # On Linux, set a user-writable npm prefix to avoid EACCES errors
      if [ "$OS_TYPE" = "linux" ]; then
        local npm_prefix="${HOME}/.npm-global"
        if [ "$(npm config get prefix)" != "$npm_prefix" ]; then
          run_command "mkdir -p $npm_prefix"
          run_command "npm config set prefix $npm_prefix"
          export PATH="$npm_prefix/bin:$PATH"
          print_success "npm global prefix set to $npm_prefix."
        fi
      fi
      if [ "$DRY_RUN" = false ]; then
        while read -r package; do
          if [ -n "$package" ]; then
            run_command "npm install -g $package"
          fi
        done <"$NPM_GLOBAL_FILE"
      else
        print_warning "[DRY RUN] Would install packages from $NPM_GLOBAL_FILE"
      fi
      print_success "Global npm packages installed."
    else
      print_warning "npm not found. Skipping npm package installation."
    fi
  else
    print_warning "$NPM_GLOBAL_FILE not found. Skipping."
  fi

  # 4. Install Pipx Packages
  print_header "Installing Pipx Packages..."
  if [ -f "$PIPX_PACKAGES_FILE" ]; then
    if command -v pipx &>/dev/null; then
      if [ "$DRY_RUN" = false ]; then
        while read -r package; do
          if [ -n "$package" ]; then
            run_command "pipx install $package"
          fi
        done <"$PIPX_PACKAGES_FILE"
      else
        print_warning "[DRY RUN] Would install packages from $PIPX_PACKAGES_FILE"
      fi
      print_success "Pipx packages installed."
    else
      print_warning "pipx not found. Skipping pipx package installation."
    fi
  else
    print_warning "$PIPX_PACKAGES_FILE not found. Skipping."
  fi

  # 5. Install Bun Packages
  print_header "Installing Bun Packages..."
  if [ -f "$BUN_PACKAGES_FILE" ]; then
    if command -v bun &>/dev/null; then
      if [ "$DRY_RUN" = false ]; then
        while read -r package; do
          if [ -n "$package" ]; then
            run_command "bun add -g $package"
          fi
        done <"$BUN_PACKAGES_FILE"
      else
        print_warning "[DRY RUN] Would install packages from $BUN_PACKAGES_FILE"
      fi
      print_success "Bun packages installed."
    else
      print_warning "bun not found. Skipping bun package installation."
    fi
  else
    print_warning "$BUN_PACKAGES_FILE not found. Skipping."
  fi

  run_stow

  # 6. macOS-only: Apply cutler configuration
  if [ "$OS_TYPE" = "macos" ]; then
    print_header "Applying cutler configuration..."
    if command -v cutler &>/dev/null; then
      run_command "cutler apply"
      if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
        print_error "cutler apply command failed."
        exit 1
      fi
      print_success "cutler configuration applied."
    else
      print_warning "cutler not found. Skipping."
    fi

    print_header "Installing custom scripts..."
    if [ -d "scripts/Nvim.app" ]; then
      run_command "cp -R scripts/Nvim.app /Applications/"
      print_success "Nvim.app copied to /Applications."
    else
      print_warning "scripts/Nvim.app not found. Skipping."
    fi
  fi

  echo -e "
${C_GREEN}All done! Your dotfiles are set up.${NC}
"
}

# --- Backup ---
# Backs up the current system state: package lists, npm/pipx/bun globals,
# and commits changes to git.
backup() {
  print_header "Starting Backup... (platform: ${OS_TYPE}, pkg manager: ${PKG_MANAGER})"

  # Backup system packages
  if [ "$OS_TYPE" = "macos" ]; then
    backup_macos_packages
  elif [ "$OS_TYPE" = "linux" ]; then
    backup_linux_packages
  fi

  # Backup Global NPM Packages
  print_header "Backing up Global NPM Packages..."
  if command -v npm &>/dev/null; then
    if [ "$DRY_RUN" = false ]; then
      npm list -g --depth=0 --parseable --silent | awk -F/ '{print $NF}' | grep -vE '^(npm|corepack|lib|node_modules)$' >"$NPM_GLOBAL_FILE"
      print_success "Global npm packages backed up to $NPM_GLOBAL_FILE."
    else
      print_warning "[DRY RUN] Would backup global npm packages to $NPM_GLOBAL_FILE"
    fi
  else
    print_warning "npm not found. Skipping npm backup."
  fi

  # Backup Pipx Packages
  print_header "Backing up Pipx Packages..."
  if command -v pipx &>/dev/null; then
    if [ "$DRY_RUN" = false ]; then
      pipx list --short | awk '{print $1}' >"$PIPX_PACKAGES_FILE"
      print_success "Pipx packages backed up to $PIPX_PACKAGES_FILE."
    else
      print_warning "[DRY RUN] Would backup pipx packages to $PIPX_PACKAGES_FILE"
    fi
  else
    print_warning "pipx not found. Skipping pipx backup."
  fi

  # Backup Bun Packages
  print_header "Backing up Bun Packages..."
  if command -v bun &>/dev/null; then
    if [ "$DRY_RUN" = false ]; then
      bun pm ls -g | grep -v node_modules | awk '{print $2}' | sed 's/@[^@]*$//' >"$BUN_PACKAGES_FILE"
      print_success "Bun packages backed up to $BUN_PACKAGES_FILE."
    else
      print_warning "[DRY RUN] Would backup bun packages to $BUN_PACKAGES_FILE"
    fi
  else
    print_warning "bun not found. Skipping bun backup."
  fi

  run_stow "backup"

  if [ "$DRY_RUN" = false ]; then
    if [ -n "$(git status --porcelain)" ]; then
      print_warning "Changes detected. Committing and pushing..."
      run_command "git add ."
      run_command "git commit -m 'chore(backup): automated backup of dotfiles changes'"
      run_command "git pull origin main --rebase"
      run_command "git push origin main"
      run_command "\"${SCRIPT_DIR}/scripts/notify.sh\" --title 'Dotfiles' --message 'Changes detected. dotfiles updated'"
      print_success "Changes committed and pushed."
    else
      print_success "No changes detected. Nothing to commit."
    fi
  fi
}

# --- macOS Backup ---
# Dumps the current Homebrew state into a Brewfile.
backup_macos_packages() {
  print_header "Backing up Homebrew packages..."
  run_command "brew bundle dump --all --force --describe --file=.config/Brewfile"
  if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
    print_error "Brew bundle dump command failed."
    exit 1
  fi
  print_success "Brewfile updated successfully."
}

# --- Linux Backup ---
# Exports the list of explicitly installed packages for the detected distro.
backup_linux_packages() {
  print_header "Backing up system packages ($PKG_MANAGER)..."
  if [ "$DRY_RUN" = false ]; then
    case "$PKG_MANAGER" in
    apt)
      apt-mark showmanual | sort >"$PKG_LIST_FILE"
      ;;
    dnf)
      dnf repoquery --userinstalled --qf '%{name}' | sort >"$PKG_LIST_FILE"
      ;;
    pacman)
      pacman -Qqe | sort >"$PKG_LIST_FILE"
      ;;
    zypper)
      zypper se --installed-only | awk -F'|' '/^i/ {gsub(/^ +| +$/, "", $2); print $2}' | sort >"$PKG_LIST_FILE"
      ;;
    esac
    print_success "System packages backed up to $PKG_LIST_FILE."
  else
    print_warning "[DRY RUN] Would backup $PKG_MANAGER packages to $PKG_LIST_FILE"
  fi
}

# --- Schedule ---
# Registers an hourly cron job that runs the backup command.
schedule() {
  print_header "Scheduling Hourly Backups..."

  local script_path
  script_path=$(realpath "$0")

  local cron_job_path="PATH=/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
  local cron_job="0 * * * * $script_path backup"

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would check for and add the following cron job:"
    echo "$cron_job"
    return
  fi

  if ! crontab -l | grep -Fq "$cron_job_path"; then
    (
      crontab -l 2>/dev/null
      echo "$cron_job_path"
    ) | crontab -
    if [ $? -ne 0 ]; then
      print_error "Failed to set crontab path."
      exit 1
    fi
    print_success "crontab PATH is set."
  else
    print_success "crontab PATH is already set."
  fi

  if ! crontab -l | grep -Fq "$cron_job"; then
    (
      crontab -l 2>/dev/null
      echo "$cron_job"
    ) | crontab -
    if [ $? -ne 0 ]; then
      print_error "Failed to schedule backup."
      exit 1
    fi
    print_success "Backup scheduled to run hourly."
  else
    print_success "Backup is already scheduled."
  fi
}

# --- Argument Parsing ---
COMMAND=""

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
  -h | --help)
    print_help
    exit 0
    ;;
  -d | --dry-run)
    DRY_RUN=true
    shift
    ;;
  restore | backup | schedule)
    COMMAND=$key
    shift
    ;;
  *)
    print_error "Unknown option: $1"
    print_help
    exit 1
    ;;
  esac
done

# --- Main Script ---
if [ -z "$COMMAND" ]; then
  print_error "No command specified."
  print_help
  exit 1
fi

# Detect platform before running any command
detect_platform
detect_package_manager

if [ "$DRY_RUN" = true ]; then
  print_warning "Running in dry-run mode. No commands will be executed."
fi

print_logo
print_success "Detected platform: ${OS_TYPE} (${PKG_MANAGER})$([ "$IS_WSL" = true ] && echo ' [WSL]')"
echo

case $COMMAND in
restore)
  restore
  ;;
backup)
  backup
  ;;
schedule)
  schedule
  ;;
esac
