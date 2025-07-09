#!/usr/bin/env sh

# Aerospace Mode Indicator
# This creates the mode indicator that shows when not in main mode (positioned in center)

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Aerospace Mode Indicator (centered, separate segment when visible)
sketchybar --add item aerospace_mode center \
           --set aerospace_mode \
           drawing=off \
           background.drawing=off \
           padding_left=10 \
           padding_right=10 \
           icon.color=$CONTENT_PRIMARY \
           icon.padding_left=0 \
           icon.padding_right=6 \
           label.color=$CONTENT_PRIMARY \
           label.padding_left=0 \
           label.padding_right=0 \
           label.font="SF Pro:Medium:11.0" \
           script="$PLUGIN_DIR/workspace/aerospace_mode.sh" \
           click_script="aerospace mode main && $PLUGIN_DIR/workspace/aerospace_mode.sh main" \
           --subscribe aerospace_mode aerospace_mode_change
