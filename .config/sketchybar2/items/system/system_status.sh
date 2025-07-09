#!/usr/bin/env sh

# System Status Items
# This creates the right-side system status items

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Clock (rightmost item in system status - needs right padding)
sketchybar --add item clock right \
           --set clock \
           update_freq=10 \
           icon.drawing=off \
           background.drawing=off \
           padding_right=10 \
           script="$PLUGIN_DIR/system/clock.sh" \
           click_script="open -a Clock"

# Calendar  
sketchybar --add item calendar right \
           --set calendar \
           update_freq=10 \
           icon.drawing=off \
           background.drawing=off \
           script="$PLUGIN_DIR/system/calendar.sh" \
           click_script="open -a Calendar"

# Volume (fix cut-off text with more padding)
sketchybar --add item volume right \
           --set volume \
           background.drawing=off \
           padding_right=15 \
           script="$PLUGIN_DIR/system/volume.sh" \
           click_script="$PLUGIN_DIR/system/volume_click.sh" \
           --subscribe volume volume_change

# Battery
sketchybar --add item battery right \
           --set battery \
           update_freq=120 \
           background.drawing=off \
           script="$PLUGIN_DIR/system/battery.sh" \
           --subscribe battery system_woke power_source_change 