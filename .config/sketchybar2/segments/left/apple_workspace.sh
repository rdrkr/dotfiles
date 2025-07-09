#!/usr/bin/env bash

# Left Segment 1: Apple Logo + Workspaces
# This segment groups the Apple logo with workspace items

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Read workspace items from temp file (created by workspace items)
WORKSPACE_ITEMS=($(cat /tmp/sketchybar_workspace_items 2>/dev/null || echo ""))

# Create bracket with Apple logo and workspaces
if [ ${#WORKSPACE_ITEMS[@]} -gt 0 ]; then
    sketchybar --add bracket apple_spaces apple.logo "${WORKSPACE_ITEMS[@]}" \
               --set apple_spaces background.color=$SEGMENT_PRIMARY \
                                 background.corner_radius=16 \
                                 background.height=32
else
    # Fallback if no workspaces found
    sketchybar --add bracket apple_spaces apple.logo \
               --set apple_spaces background.color=$SEGMENT_PRIMARY \
                                 background.corner_radius=16 \
                                 background.height=32
fi