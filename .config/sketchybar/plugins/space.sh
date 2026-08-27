#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/icons.sh"

AEROSPACE_FOCUSED_WORKSPACE=$(aerospace list-workspaces --focused)

# Update space icons based on focused workspace
for i in $(aerospace list-workspaces --all); do
  if [[ $i -eq $AEROSPACE_FOCUSED_WORKSPACE ]]; then
    sketchybar --set space.$i icon="$PACMAN" background.color="$TRANSPARENT"
  else
    sketchybar --set space.$i icon="$GHOST" background.color="$TRANSPARENT"
  fi
done

# Update current space display
sketchybar --set current_space icon="$AEROSPACE_FOCUSED_WORKSPACE"
