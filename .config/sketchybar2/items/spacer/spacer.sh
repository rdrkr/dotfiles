#!/usr/bin/env bash

# General Spacer Function
# Creates invisible spacers to separate segments visually
# Usage: add_spacer <name> <position> [width]

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Function to add a spacer (available for future use)
add_spacer() {
    local name="$1"
    local position="$2"
    local width="${3:-20}"  # Default width is 20px
    
    sketchybar --add item "$name" "$position" \
               --set "$name" \
               background.drawing=off \
               icon.drawing=off \
               label.drawing=off \
               width="$width"
}

# Spacing handled by segment padding_right instead of spacer items