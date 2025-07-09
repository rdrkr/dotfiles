#!/bin/bash

# --- Configuration ---
DRY_RUN=false

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
    echo "██████╗   ██████╗ ████████╗ ███████╗ ██╗  ██╗     ███████╗ ███████╗"
    echo -e "${C_BLUE}"
    echo "██╔══██╗ ██╔═══██╗ ╚══██╔══╝ ██╔════╝ ██║ ██║      ██╔════╝ ██╔════╝"
    echo -e "${C_SAPPHIRE}"
    echo "██║  ██║ ██║   ██║    ██║    █████╗   ██║ ██║      █████╗   ███████╗"
    echo -e "${C_SKY}"
    echo "██║  ██║ ██║   ██║    ██║    ██╔══╝   ██║ ██║      ██╔════╝ ╚════██║"
    echo -e "${C_TEAL}"
    echo "██████╔╝ ╚██████╔╝    ██║    ██╗      ██║ ███████╗ ███████║ ███████║"
    echo -e "${C_GREEN}"
    echo "╚═════╝   ╚═════╝     ╚═╝    ╚══════╝ ╚═╝ ╚══════╝ ╚══════╝ ╚══════╝"
    echo -e "${NC}"
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

restore() {
    print_header "Starting Restore..."

    # 1. Install Homebrew
    print_header "Checking for Homebrew..."
    if ! command -v brew &> /dev/null; then
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
            if [[ ! $REPLY =~ ^[Yy]$ ]]
            then
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

    # 3. Run stow
    print_header "Running stow..."
    if command -v stow &> /dev/null; then
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

    echo -e "\n${C_GREEN}All done! Your dotfiles are set up.${NC}\n"
}

backup() {
    print_header "Starting Backup..."
    run_command "brew bundle dump --all --force --describe"
    if [ $? -ne 0 ] && [ "$DRY_RUN" = false ]; then
        print_error "Brew bundle dump command failed."
        exit 1
    fi
    print_success "Brewfile updated successfully."

    if [ "$DRY_RUN" = false ]; then
        if [ -n "$(git status --porcelain Brewfile)" ]; then
            print_warning "Brewfile has changes. Committing and pushing..."
            run_command "git add Brewfile"
            run_command "git commit -m 'Update Brewfile'"
            run_command "git push"
            print_success "Brewfile changes committed and pushed."
        else
            print_success "No changes to Brewfile. Nothing to commit."
        fi
    fi
}

# --- Argument Parsing ---
COMMAND=""

while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -h|--help)
        print_help
        exit 0
        ;;
        -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
        restore|backup)
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
esac