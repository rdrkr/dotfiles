#!/usr/bin/env bash

# Enhanced front app click script
# $BUTTON = "left", "right", or "middle"

case "$BUTTON" in
    "left")
        # Left click: Open Mission Control to see all spaces and windows
        osascript -e 'tell application "System Events" to key code 126 using control down'
        ;;
    "right")
        # Right click: Open Launchpad to see all apps
        osascript -e 'tell application "System Events" to key code 131'
        ;;
    "middle")
        # Middle click: Trigger the actual App Switcher (Cmd+Tab)
        osascript -e 'tell application "System Events" to key code 48 using command down'
        ;;
    *)
        # Default: Open Mission Control
        osascript -e 'tell application "System Events" to key code 126 using control down'
        ;;
esac 