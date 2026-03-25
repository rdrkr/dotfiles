#!/bin/bash

# --- Go to dotfiles repo directory ---
# Store the original directory and change to the script's directory.
# This allows the script to be run from any location.
ORIGINAL_DIR=$(pwd)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "$SCRIPT_DIR" || exit
# Restore the original directory when the script exits.
trap 'cd "$ORIGINAL_DIR"' EXIT

# --- Configuration ---
DRY_RUN=false

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
  echo "  backup       Update Brewfile with current setup"
  echo "  schedule     Schedule hourly backups using cron"
  echo ""
  echo "Options:"
  echo "  -h, --help     Show this help message and exit"
  echo "  -d, --dry-run  Run the script in dry-run mode (no changes will be made)"
}

run_command() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${C_YELLOW}[DRY RUN] Would execute: $1${NC}"
  else
    eval "$1"
  fi
}

run_stow() {
  print_header "Running stow..."
  if command -v stow &>/dev/null; then
    run_command "stow ."
    if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
      print_error "Stow command failed."
      exit 1
    fi
    print_success "Stow command completed successfully."
  else
    print_error "Stow is not installed. Please install it first (e.g., 'brew install stow')."
    exit 1
  fi
}

restore() {
  print_header "Starting Restore..."

  # 1. Install Homebrew
  print_header "Checking for Homebrew..."
  if ! command -v brew &>/dev/null; then
    print_warning "xcode command line tools. Installing..."
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

  # 2. Install formulas, casks, and VS Code extensions from Brewfile
  print_header "Installing from Brewfile..."
  if [ -f "Brewfile" ]; then
    if [ "$DRY_RUN" = false ]; then
      read -p "Are you logged into the App Store? (y/n) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Please log in to the App Store to continue."
        run_command "open -a 'App Store'"
        exit 1
      fi
    fi
    run_command "brew bundle --file=Brewfile"
    if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
      print_error "Brew bundle command failed."
      exit 1
    fi
    print_success "Brewfile dependencies installed."
  else
    print_warning "Brewfile not found. Skipping brew bundle."
  fi

  # 3. Setup default macOS applications with infat
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

  # 4. Install Global NPM Packages
  print_header "Installing Global NPM Packages..."
  if [ -f "$NPM_GLOBAL_FILE" ]; then
    if command -v npm &>/dev/null; then
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

  # 5. Install Pipx Packages
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

  # 6. Install Bun Packages
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

  echo -e "
${C_GREEN}All done! Your dotfiles are set up.${NC}
"
}

backup() {
  print_header "Starting Backup..."
  run_command "brew bundle dump --all --force --describe"
  if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
    print_error "Brew bundle dump command failed."
    exit 1
  fi
  print_success "Brewfile updated successfully."

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

  run_stow

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

if [ "$DRY_RUN" = true ]; then
  print_warning "Running in dry-run mode. No commands will be executed."
fi

print_logo

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
