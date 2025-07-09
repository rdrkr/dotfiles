#!/usr/bin/env bash

# SketchyBar Bar Appearance Configuration
# This file defines the main bar appearance and properties

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Main Bar Configuration
# Transparent main bar to let segments show through
bar=(
  height=35
  color=$TRANSPARENT
  shadow=off
  position=top
  sticky=on
  padding_right=12
  padding_left=12
  corner_radius=18
  y_offset=3
  blur_radius=0
  notch_width=0
)

# Apply bar configuration
sketchybar --bar "${bar[@]}"