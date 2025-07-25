#!/usr/bin/env bash

sketchybar --add item battery right \
  --set battery \
  update_freq=60 \
  icon.color="$CYAN" \
  icon.padding_left=10 \
  label.padding_right=10 \
  label.color="$CYAN" \
  background.height=26 \
  background.corner_radius="$CORNER_RADIUS" \
  background.padding_right=5 \
  background.border_width="$BORDER_WIDTH" \
  background.border_color="$CYAN" \
  background.color="$BAR_COLOR" \
  background.drawing=on \
  script="$PLUGIN_DIR/power.sh" \
  --subscribe battery power_source_change
