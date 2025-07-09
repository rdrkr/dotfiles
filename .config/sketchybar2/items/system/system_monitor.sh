#!/usr/bin/env sh

# System Monitor Items
# This creates a second right-side segment with system monitoring

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Temperature (rightmost item in system monitor segment)
sketchybar --add item temperature right \
           --set temperature \
           update_freq=5 \
                   icon="$TEMPERATURE" \
        icon.color=$STATE_WARNING \
           background.drawing=off \
           padding_right=20 \
           script="$PLUGIN_DIR/system/temperature.sh"

# Memory Usage
sketchybar --add item memory right \
           --set memory \
           update_freq=5 \
                   icon="$MEMORY" \
        icon.color=$INTERACTIVE_PRIMARY \
           background.drawing=off \
           script="$PLUGIN_DIR/system/memory.sh"

# CPU Usage (simple version, different from the complex cpu.sh)
sketchybar --add item cpu_simple right \
           --set cpu_simple \
           update_freq=2 \
                   icon="$CPU" \
        icon.color=$STATE_SUCCESS \
           background.drawing=off \
           script="$PLUGIN_DIR/system/cpu_simple.sh"