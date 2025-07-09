#!/usr/bin/env bash

# SketchyBar Default Item Settings
# This file defines the default appearance for all items

# Load global configuration  
source "$HOME/.config/sketchybar/config/globals.sh"

# Default Item Settings
defaults=(
  updates=when_shown
  icon.font="$FONT:Regular:16.0"
  icon.color=$CONTENT_PRIMARY
  icon.padding_left=5
  icon.padding_right=3
  label.font="$FONT:Regular:10.0"
  label.color=$CONTENT_PRIMARY
  label.padding_left=0
  label.padding_right=0
  background.padding_right=$PADDINGS
  background.padding_left=5
  background.height=30
  background.corner_radius=10
  popup.background.border_width=0
  popup.background.corner_radius=16
  popup.background.color=$POPUP_BACKGROUND_COLOR
  popup.background.shadow.color=$POPUP_SHADOW_COLOR
  popup.blur_radius=30
  popup.background.shadow.drawing=on
)

# Apply default settings
sketchybar --default "${defaults[@]}"