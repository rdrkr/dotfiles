#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/icons.sh"

AEROSPACE_FOCUSED_WORKSPACE=$(aerospace list-workspaces --focused)

# Update the current space icon to show the focused workspace
sketchybar --set current_space icon="$AEROSPACE_FOCUSED_WORKSPACE"
