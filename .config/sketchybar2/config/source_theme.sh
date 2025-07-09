#!/bin/sh

# Simple theme source wrapper for sh compatibility
# This file directly sources the current theme without using bash-specific features

# Get the current theme
THEME_DIR="$HOME/.config/sketchybar/themes"
CURRENT_THEME_FILE="$THEME_DIR/.current-theme"

if [ -f "$CURRENT_THEME_FILE" ]; then
    CURRENT_THEME=$(cat "$CURRENT_THEME_FILE")
else
    CURRENT_THEME="catppuccin"
fi

# Source the theme file directly
THEME_FILE="$THEME_DIR/$CURRENT_THEME.theme.sh"
if [ -f "$THEME_FILE" ]; then
    . "$THEME_FILE"
    export SKETCHYBAR_THEME="$CURRENT_THEME"
else
    echo "Warning: Theme file $THEME_FILE not found" >&2
fi

# Also source icons
ICONS_FILE="$HOME/.config/sketchybar/icons.sh"
if [ -f "$ICONS_FILE" ]; then
    . "$ICONS_FILE"
fi
