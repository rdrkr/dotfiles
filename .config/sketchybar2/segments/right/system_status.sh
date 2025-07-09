#!/usr/bin/env bash

# Right Segment: System Status (rightmost, with padding to create gap)
# This segment groups system status indicators

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Create bracket for system status
sketchybar --add bracket system_status github.bell battery volume calendar clock \
           --set system_status position=right \
                              background.color=$SEGMENT_PRIMARY \
                              background.corner_radius=16 \
                              background.height=32