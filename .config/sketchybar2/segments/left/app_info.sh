#!/usr/bin/env bash

# Left Segment 2: App Info (chevron + front app)
# This segment groups the application information display

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Create bracket for app info
sketchybar --add bracket app_info chevron front_app \
           --set app_info background.color=$SEGMENT_PRIMARY \
                         background.corner_radius=16 \
                         background.height=32