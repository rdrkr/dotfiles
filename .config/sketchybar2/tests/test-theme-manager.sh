#!/usr/bin/env bash

# Test script for the theme manager

export SKETCHYBAR_CI=1

# Exit immediately if a command exits with a non-zero status.
set -e

THEME_DIR="themes"
THEME_MANAGER="$THEME_DIR/theme-manager.sh"

# Helper function to run a test
run_test() {
    echo "Running test: $1"
    eval "$1"
    echo "Test passed: $1"
    echo
}

# Test 1: List themes
test_list_themes() {
    local themes=$($THEME_MANAGER list)
    if [[ ! "$themes" =~ "catppuccin" ]]; then
        echo "FAIL: 'catppuccin' not found in theme list"
        exit 1
    fi
    if [[ ! "$themes" =~ "nord" ]]; then
        echo "FAIL: 'nord' not found in theme list"
        exit 1
    fi
}

# Test 2: Apply a theme
test_apply_theme() {
    $THEME_MANAGER nord
    local current_theme=$(cat "$THEME_DIR/.current-theme")
    if [[ "$current_theme" != "nord" ]]; then
        echo "FAIL: Could not apply theme 'nord'"
        exit 1
    fi
}

# Test 3: Cycle to the next theme
test_cycle_theme() {
    # Set current theme to nord
    echo "nord" > "$THEME_DIR/.current-theme"

    # Cycle to the next theme (should be tokyo-night)
    $THEME_MANAGER
    local current_theme=$(cat "$THEME_DIR/.current-theme")
    if [[ "$current_theme" != "tokyo-night" ]]; then
        echo "FAIL: Could not cycle to the next theme"
        exit 1
    fi
}

# Test 4: Load theme colors
test_load_theme() {
    # Set current theme to dracula
    echo "dracula" > "$THEME_DIR/.current-theme"

    # Load the theme
    eval "$(./$THEME_MANAGER load)"

    # Check if the theme name is exported
    if [[ "$SKETCHYBAR_THEME" != "dracula" ]]; then
        echo "FAIL: Could not load theme colors"
        exit 1
    fi
}

# Run all tests
run_test test_list_themes
run_test test_apply_theme
run_test test_cycle_theme
run_test test_load_theme

echo "All tests passed!"
