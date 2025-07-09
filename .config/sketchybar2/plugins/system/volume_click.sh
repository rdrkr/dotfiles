#!/usr/bin/env sh

toggle_mute() {
  sketchybar --set "$NAME" popup.drawing=off

  MUTED=$(osascript -e 'output muted of (get volume settings)')

  if [ "$MUTED" = "false" ]; then
    osascript -e 'set volume output muted true'
  else
    osascript -e 'set volume output muted false'
  fi
  exit 0
}

toggle_devices() {
  which SwitchAudioSource >/dev/null || exit 0
  source "$HOME/.config/sketchybar/config/source_theme.sh"

  args=(--remove '/volume.device\.*/' --set "$NAME" popup.drawing=toggle)
  COUNTER=0
  CURRENT="$(SwitchAudioSource -t output -c)"
  while IFS= read -r device; do
    COLOR=$CONTENT_DISABLED
    if [ "${device}" = "$CURRENT" ]; then
      COLOR=$INTERACTIVE_SELECTED
    fi
    args+=(--add item volume.device.$COUNTER popup."$NAME" \
           --set volume.device.$COUNTER label="${device}" \
                                        label.color="$COLOR" \
                 click_script="SwitchAudioSource -s \"${device}\" && sketchybar --set /volume.device\.*/ label.color=$CONTENT_DISABLED --set \$NAME label.color=$INTERACTIVE_SELECTED")
    COUNTER=$((COUNTER+1))
  done <<< "$(SwitchAudioSource -a -t output)"

  sketchybar -m "${args[@]}"
}

if [ "$BUTTON" = "right" ] || [ "$MODIFIER" = "shift" ]; then
  toggle_devices
else
  toggle_mute
fi
