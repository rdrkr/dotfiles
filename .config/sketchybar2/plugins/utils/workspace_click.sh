#!/usr/bin/env bash

# Enhanced workspace click script with multiple click types
# $1 = workspace ID
# $BUTTON = "left", "right", or "middle"
# $MODIFIER = "shift", "cmd", "alt", "ctrl" (if pressed)

WORKSPACE_ID="$1"

case "$BUTTON" in
    "left")
        # Left click: Switch to workspace
        aerospace workspace "$WORKSPACE_ID"
        ;;
    "right")
        # Right click: Move current window to workspace and follow
        aerospace move-node-to-workspace "$WORKSPACE_ID"
        aerospace workspace "$WORKSPACE_ID"
        ;;
    "middle")
        # Middle click: Move current window to workspace but stay
        aerospace move-node-to-workspace "$WORKSPACE_ID"
        ;;
    *)
        # Default: Switch to workspace
        aerospace workspace "$WORKSPACE_ID"
        ;;
esac

# Refresh workspace indicators
sketchybar --trigger aerospace_workspace_change 