#!/usr/bin/env bash

# SketchyBar plugin for Aerospace mode indicator
# Shows when Aerospace is in a mode other than "main"

# This script is called directly with the mode as the first argument
# from the aerospace configuration triggers

MODE="$1"

# Debug logging
echo "DEBUG: Called with MODE=$MODE, AEROSPACE_MODE=$AEROSPACE_MODE" >> /tmp/aerospace_mode.log

# If no mode is provided or it's main mode, hide the indicator
if [ -z "$MODE" ] || [ "$MODE" = "main" ]; then
    sketchybar --set aerospace_mode \
        drawing=off \
        label="" \
        icon=""
else
    # Show the mode indicator with appropriate styling
    case "$MODE" in
        "service")
            ICON="󰒓"  # Service/settings icon
            LABEL="SERVICE"
            ;;
        "resize")
            ICON="󰩨"  # Resize icon
            LABEL="RESIZE"
            ;;
        "move")
            ICON="󰆾"  # Move icon
            LABEL="MOVE"
            ;;
        *)
            ICON="󰘲"  # Default mode icon
            LABEL="$MODE"
            ;;
    esac

    sketchybar --set aerospace_mode \
        drawing=on \
        icon="$ICON" \
        label="$LABEL" \
        background.drawing=on
fi
