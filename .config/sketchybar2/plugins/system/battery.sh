#!/bin/sh

# Load global configuration
source "$HOME/.config/sketchybar/config/source_theme.sh"

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"
BATTERY_INFO="$(pmset -g batt)"

# Check if this is a desktop (AC only) or laptop (has battery)
if [ "$PERCENTAGE" = "" ]; then
  # No battery detected - this is likely a desktop Mac
  if [[ "$CHARGING" != "" ]]; then
    # AC Power detected
    ICON="󰚥"  # AC power icon
    LABEL="AC"
  else
    # Fallback for unknown power state
    ICON="󰚥"
    LABEL="PWR"
  fi
else
  # Battery detected - this is a laptop/portable device
  case "${PERCENTAGE}" in
    9[0-9]|100) ICON="󰁹"  # Full battery
    ;;
    [6-8][0-9]) ICON="󰂀"  # High battery
    ;;
    [3-5][0-9]) ICON="󰁾"  # Medium battery
    ;;
    [1-2][0-9]) ICON="󰁻"  # Low battery
    ;;
    *) ICON="󰂎"          # Very low/critical battery
  esac

  # Override with charging icon if plugged in
  if [[ "$CHARGING" != "" ]]; then
    ICON="󰂄"  # Charging icon
  fi

  LABEL="${PERCENTAGE}%"
fi

# Determine colors based on battery state
if [[ "$CHARGING" != "" ]]; then
  # Charging - use success color
  COLOR=$STATE_SUCCESS
elif [ "$PERCENTAGE" != "" ] && [ "$PERCENTAGE" -le 20 ]; then
  # Low battery - use error color
  COLOR=$STATE_ERROR
elif [ "$PERCENTAGE" != "" ] && [ "$PERCENTAGE" -le 40 ]; then
  # Medium battery - use warning color
  COLOR=$STATE_WARNING
else
  # Normal state - use default icon color
  COLOR=$CONTENT_PRIMARY
fi

# Update the item with appropriate icon, label, and color
sketchybar --set "$NAME" icon="$ICON" label="$LABEL" icon.color="$COLOR"
