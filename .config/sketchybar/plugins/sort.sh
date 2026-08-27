#!/bin/bash

source "$HOME/.config/sketchybar/environment.sh"

move_app_to_workspace() {
    local app_name=$1
    local workspace_id=$2
    
    # Get the window ID for the app using aerospace
    local window_id=$(aerospace list-windows | grep "$app_name" | head -1 | awk -F'|' '{print $1}' | tr -d ' ')
    
    if [[ -n "$window_id" ]]; then
        aerospace move-window-to-workspace "$window_id" "$workspace_id"
        echo "Moved $app_name to workspace $workspace_id."
    else
        echo "No windows found for $app_name."
    fi
}

# For now, we'll use a simple notification since the APPS and APP_SPACES are removed
# You can customize this based on your needs
osascript -e 'display notification "Sorting functionality needs to be configured for aerospace" with title "Sorting"'