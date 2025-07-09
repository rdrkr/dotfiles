#!/usr/bin/env sh

# Aerospace Workspace Items with App Icon Expansion
# This creates workspace indicators that expand to show app icons when active

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# Get all workspaces from aerospace and create items for them
WORKSPACE_ITEMS=()
WORKSPACE_LIST=($(aerospace list-workspaces --all))
WORKSPACE_COUNT=${#WORKSPACE_LIST[@]}

for i in "${!WORKSPACE_LIST[@]}"; do
    sid="${WORKSPACE_LIST[$i]}"
    WORKSPACE_ITEMS+=("space.$sid")
    
    # Add padding to the last workspace item
    if [ $((i + 1)) -eq $WORKSPACE_COUNT ]; then
        PADDING_RIGHT=10
    else
        PADDING_RIGHT=3
    fi
    
    sketchybar --add item space.$sid left \
        --subscribe space.$sid aerospace_workspace_change \
        --set space.$sid \
        icon="$sid" \
        icon.font="MesloLGS Nerd Font:Regular:13.0" \
        icon.color=$WORKSPACE_UNFOCUSED \
        icon.padding_left=10 \
        icon.padding_right=4 \
        icon.drawing=on \
        label="" \
        label.color=$CONTENT_INVERSE \
        label.font="sketchybar-app-font:Regular:13.0" \
        label.drawing=off \
        label.padding_left=2 \
        label.padding_right=12 \
        label.y_offset=-1 \
        background.drawing=off \
        padding_right=$PADDING_RIGHT \
        update_freq=2 \
        click_script="$PLUGIN_DIR/utils/workspace_click.sh $sid" \
        script="$PLUGIN_DIR/workspace/aerospace.sh $sid"
done

# Export workspace items array for use in main config
echo "${WORKSPACE_ITEMS[@]}" > /tmp/sketchybar_workspace_items 