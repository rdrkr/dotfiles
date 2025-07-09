#!/usr/bin/env bash

# Center Segment: Aerospace Mode (when visible)
# This segment displays the current aerospace mode

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Create bracket for aerospace mode
sketchybar --add bracket aerospace_mode_bracket aerospace_mode \
           --set aerospace_mode_bracket background.color=$INTERACTIVE_PRIMARY \
                                       background.corner_radius=16 \
                                       background.height=32