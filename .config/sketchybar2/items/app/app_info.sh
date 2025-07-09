#!/usr/bin/env sh

# App Info Items
# This creates the chevron separator and front app display

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Chevron separator
sketchybar --add item chevron left \
           --set chevron \
           icon=󰅂 \
           label.drawing=off \
           background.drawing=off

# Front app display (rightmost item in app_info segment)
sketchybar --add item front_app left \
           --set front_app \
           icon.drawing=on \
           background.drawing=off \
           padding_right=20 \
           script="$PLUGIN_DIR/utils/front_app.sh" \
           click_script="$PLUGIN_DIR/utils/front_app_click.sh" \
           --subscribe front_app front_app_switched 