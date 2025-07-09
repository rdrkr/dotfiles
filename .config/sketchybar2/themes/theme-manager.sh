#!/usr/bin/env bash

# SketchyBar Theme Manager
# Consolidates theme switching and loading logic

THEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_THEME_FILE="$THEME_DIR/.current-theme"

# Function to get current theme
get_current_theme() {
    if [ -f "$CURRENT_THEME_FILE" ]; then
        cat "$CURRENT_THEME_FILE"
    else
        echo "catppuccin" # Default theme
    fi
}

# Function to set current theme
set_current_theme() {
    echo "$1" > "$CURRENT_THEME_FILE"
}

# Function to load the current theme's colors
load_theme() {
    local current_theme=$(get_current_theme)
    local theme_file="$THEME_DIR/$current_theme.theme.sh"

    if [ ! -f "$theme_file" ]; then
        echo "Warning: Theme '$current_theme' not found, falling back to catppuccin" >&2
        current_theme="catppuccin"
        theme_file="$THEME_DIR/$current_theme.theme.sh"
        set_current_theme "$current_theme"
    fi

    # Always output the theme file content for sourcing
    cat "$theme_file"
    echo "export SKETCHYBAR_THEME=$current_theme"
}

# Dynamically find available themes
get_themes() {
    find "$THEME_DIR" -name "*.theme.sh" -exec basename {} .theme.sh \;
}

# Function to apply a theme and restart sketchybar
apply_theme() {
    local theme_name="$1"
    local theme_file="$THEME_DIR/$theme_name.theme.sh"

    if [ ! -f "$theme_file" ]; then
        echo "Error: Theme '$theme_name' not found!" >&2
        exit 1
    fi

    set_current_theme "$theme_name"

    # Restart sketchybar if not in CI environment
    if [ -z "$SKETCHYBAR_CI" ]; then
        sketchybar --exit 2>/dev/null
        sleep 0.5
        sketchybar &
    fi
}

# Function to cycle to the next theme
cycle_theme() {
    local current_theme=$(get_current_theme)
    local themes=($(get_themes | sort))
    local num_themes=${#themes[@]}

    for i in "${!themes[@]}"; do
        if [[ "${themes[$i]}" = "$current_theme" ]]; then
            next_index=$(( (i + 1) % num_themes ))
            apply_theme "${themes[$next_index]}"
            break
        fi
    done
}

# Main script logic
case "$1" in
    "load")
        load_theme
        ;;
    "list")
        get_themes
        ;;
    "")
        cycle_theme
        ;;
    *)
        # Allow applying a theme by name
        apply_theme "$1"
        ;;
esac
