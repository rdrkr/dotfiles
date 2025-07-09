#!/bin/sh

# Front app with icon mapping
# Uses the same icon mapping system as workspace app icons

# Load theme colors and fonts
source "$HOME/.config/sketchybar/config/source_theme.sh"

if [ "$SENDER" = "front_app_switched" ]; then
  # Get the app icon using the icon mapping
  APP_ICON=$("$HOME/.config/sketchybar/plugins/utils/icon_map.sh" "$INFO")

  # Set both icon and label
  sketchybar --set "$NAME" \
    icon="$APP_ICON" \
    icon.font="sketchybar-app-font:Regular:16.0" \
    icon.drawing=on \
    label="$INFO"

  # Debug output to verify the script is working
  echo "Front app updated: $INFO -> $APP_ICON" >> /tmp/sketchybar_debug.log
fi
