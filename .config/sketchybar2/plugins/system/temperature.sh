#!/bin/sh

# Temperature monitoring
# Attempts to get CPU temperature using available methods

# Source colors
source "$HOME/.config/sketchybar/config/source_theme.sh"

TEMP=""

# Method 1: Try istats if available (requires: gem install iStats)
if command -v istats >/dev/null 2>&1; then
    TEMP=$(istats cpu temp --value-only 2>/dev/null | head -1)
fi

# Method 2: Try powermetrics (requires sudo, commented out for security)
# if [ "$TEMP" = "" ]; then
#     TEMP=$(sudo powermetrics -n 1 -s cpu_power | grep "CPU die temperature" | awk '{print $4}' | head -1)
# fi

# Method 3: Try smc command if available
if [ "$TEMP" = "" ] && command -v smc >/dev/null 2>&1; then
    TEMP=$(smc -k TC0P -r | awk '{print $3}' | sed 's/°C//')
fi

# Fallback: Use a simulated temperature based on CPU usage if no temp available
if [ "$TEMP" = "" ]; then
    CPU_USAGE=$(top -l 1 -s 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' | cut -d. -f1)
    if [ "$CPU_USAGE" != "" ]; then
        # Simulate temperature: base temp + CPU usage factor
        TEMP=$(echo "35 + $CPU_USAGE * 0.5" | bc)
    else
        TEMP="--"
    fi
fi

# Set color based on temperature using semantic colors
if [ "$TEMP" != "--" ]; then
    TEMP_INT=$(echo "$TEMP" | cut -d. -f1)

    if [ "$TEMP_INT" -ge 80 ]; then
        COLOR=$STATE_ERROR        # Critical temperature - red
    elif [ "$TEMP_INT" -ge 70 ]; then
        COLOR=$STATE_WARNING      # High temperature - orange/yellow
    elif [ "$TEMP_INT" -ge 60 ]; then
        COLOR=$STATE_WARNING      # Medium-high temperature - orange/yellow
    else
        COLOR=$STATE_SUCCESS      # Normal temperature - green
    fi

    LABEL="${TEMP}°C"
else
    COLOR=$CONTENT_TERTIARY             # No temperature data - subtle text
    LABEL="--°C"
fi

# Update the item
sketchybar --set "$NAME" label="$LABEL" label.color="$COLOR"
