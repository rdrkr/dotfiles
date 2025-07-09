#!/usr/bin/env bash

# SketchyBar plugin for Aerospace workspace management
# This script handles workspace highlighting and app icon expansion

# Load global configuration
source "$HOME/.config/sketchybar/config/globals.sh"

# The workspace ID is passed as the first argument
WORKSPACE_ID="$1"
NAME="space.$WORKSPACE_ID"

# Get current focused workspace
CURRENT_WORKSPACE=$(aerospace list-workspaces --focused)

# Function to get app list for a workspace
get_workspace_app_list() {
    local workspace_id="$1"
    aerospace list-windows --workspace "$workspace_id" 2>/dev/null | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); if (!seen[$2]++) print $2}'
}

# Function to get app icons for a workspace with individual app highlighting
get_workspace_apps() {
    local workspace_id="$1"
    local icon_strip=""
    
    # Get currently focused app
    local focused_app=$(aerospace list-windows --focused 2>/dev/null | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')

    # Get list of apps in the workspace
    local apps=$(get_workspace_app_list "$workspace_id")

    if [ -n "$apps" ]; then
        while IFS= read -r app; do
            if [ -n "$app" ]; then
                # Get icon for the app using icon_map.sh
                local app_icon=$("$PLUGIN_DIR/utils/icon_map.sh" "$app")
                if [ -n "$app_icon" ]; then
                    # Add small dot indicator for focused app
                    if [ "$app" = "$focused_app" ]; then
                        # Focused app with small dot
                        icon_strip+=" •$app_icon "
                    else
                        # Other apps normal
                        icon_strip+=" $app_icon "
                    fi
                fi
            fi
        done <<< "$apps"
    fi

    echo "$icon_strip"
}

# Function to check if workspace contains the focused app
workspace_has_focused_app() {
    local workspace_id="$1"
    local focused_app=$(aerospace list-windows --focused 2>/dev/null | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
    local apps=$(get_workspace_app_list "$workspace_id")
    
    if [ -n "$focused_app" ] && [ -n "$apps" ]; then
        echo "$apps" | grep -q "^$focused_app$"
        return $?
    fi
    return 1
}

# Check if this workspace is currently focused
if [ "$WORKSPACE_ID" = "$CURRENT_WORKSPACE" ]; then
    # Get app icons for active workspace
    APP_ICONS=$(get_workspace_apps "$WORKSPACE_ID")
    
    # Check if workspace contains focused app for enhanced highlighting
    if workspace_has_focused_app "$WORKSPACE_ID"; then
        # Enhanced highlight when workspace contains focused app
        sketchybar --set $NAME \
            background.drawing=on \
            background.color=$WORKSPACE_FOCUSED \
            background.corner_radius=15 \
            background.border_width=1 \
            background.border_color=$BORDER_FOCUS \
            label.color=$INTERACTIVE_PRIMARY \
            icon.color=$CONTENT_INVERSE \
            label="$APP_ICONS" \
            label.drawing=on \
            label.padding_left=2 \
            label.padding_right=12 \
            label.font="sketchybar-app-font:Regular:13.0" \
            label.y_offset=-1
    else
        # Normal active workspace highlight
        sketchybar --set $NAME \
            background.drawing=on \
            background.color=$WORKSPACE_FOCUSED \
            background.corner_radius=15 \
            background.border_width=0 \
            label.color=$INTERACTIVE_PRIMARY \
            icon.color=$CONTENT_INVERSE \
            label="$APP_ICONS" \
            label.drawing=on \
            label.padding_left=2 \
            label.padding_right=12 \
            label.font="sketchybar-app-font:Regular:13.0" \
            label.y_offset=-1
    fi
else
    # Dim the inactive workspace and hide app icons
    sketchybar --set $NAME \
        background.drawing=off \
        label.color=$WORKSPACE_UNFOCUSED \
        icon.color=$WORKSPACE_UNFOCUSED \
        label="" \
        label.drawing=off
fi

# Set workspace-specific icons
case "$WORKSPACE_ID" in
    "1"|"2"|"3")
        # Numbered workspaces
        sketchybar --set $NAME icon="$WORKSPACE_ID"
        ;;
    "A")
        # AI workspace
        sketchybar --set $NAME icon="A 󰚩"
        ;;
    "B")
        # Browser workspace
        sketchybar --set $NAME icon="B 󰖟"
        ;;
    "C")
        # Calendar workspace
        sketchybar --set $NAME icon="C 󰃭"
        ;;
    "E")
        # Editor workspace
        sketchybar --set $NAME icon="E 󰷈"
        ;;
    "M")
        # Messages workspace
        sketchybar --set $NAME icon="M 󰍩"
        ;;
    "T")
        # Terminal workspace
        sketchybar --set $NAME icon="T 󰆍"
        ;;
    "Z")
        # Meeting workspace
        sketchybar --set $NAME icon="Z 󰍫"
        ;;
    *)
        # Use workspace ID as icon for other workspaces
        sketchybar --set $NAME icon="$WORKSPACE_ID"
        ;;
esac
