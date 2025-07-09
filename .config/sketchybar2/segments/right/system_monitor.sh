#!/usr/bin/env bash

# Right Segment: System Monitor
# This segment groups system monitoring indicators

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Create bracket for system monitor
sketchybar --add bracket system_monitor cpu_simple memory temperature \
           --set system_monitor position=right \
                               background.color=$SEGMENT_SECONDARY \
                               background.corner_radius=16 \
                               background.height=32