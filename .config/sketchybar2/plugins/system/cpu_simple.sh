#!/bin/sh

# Simple CPU usage monitoring
# Gets overall CPU percentage using top command

# Source current theme
source "$HOME/.config/sketchybar/config/source_theme.sh"

# Get CPU usage from top (1 second sample)
CPU_USAGE=$(top -l 1 -s 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')

if [ "$CPU_USAGE" = "" ]; then
  exit 0
fi

# Convert to integer for comparison
CPU_INT=$(echo "$CPU_USAGE" | cut -d. -f1)

# Set color based on usage using new semantic colors
if [ "$CPU_INT" -ge 80 ]; then
  COLOR=$STATE_ERROR     # High CPU usage - red
elif [ "$CPU_INT" -ge 60 ]; then
  COLOR=$STATE_WARNING   # Medium-high CPU usage - orange
elif [ "$CPU_INT" -ge 40 ]; then
  COLOR=$STATE_CAUTION          # Medium CPU usage
else
  COLOR=$STATE_SUCCESS   # Low CPU usage - green
fi

# Update the item
sketchybar --set "$NAME" label="${CPU_USAGE}%" label.color="$COLOR"
