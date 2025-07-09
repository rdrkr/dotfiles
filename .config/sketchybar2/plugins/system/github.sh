#!/bin/sh

update() {
  source "$HOME/.config/sketchybar/config/source_theme.sh"

  # GitHub-specific color mappings using semantic theme colors
  GITHUB_ISSUE=$STATE_SUCCESS           # Issues (green - actionable)
  GITHUB_DISCUSSION=$CONTENT_SECONDARY        # Discussions (neutral)
  GITHUB_PULLREQUEST=$INTERACTIVE_PRIMARY       # Pull Requests (blue - primary action)
  GITHUB_COMMIT=$CONTENT_SECONDARY            # Commits (neutral)
  GITHUB_IMPORTANT=$STATE_ERROR         # Important notifications (red)
  GITHUB_BELL_DEFAULT=$INTERACTIVE_PRIMARY      # Default bell color
  GITHUB_BELL_ACTIVE=$STATE_WARNING     # Bell with notifications

  NOTIFICATIONS="$(gh api notifications)"
  COUNT="$(echo "$NOTIFICATIONS" | jq 'length')"
  args=()
  if [ "$NOTIFICATIONS" = "[]" ]; then
    args+=(--set $NAME icon=$BELL label="0" icon.color=$GITHUB_BELL_DEFAULT)
  else
    args+=(--set $NAME icon=$BELL_DOT label="$COUNT" icon.color=$GITHUB_BELL_ACTIVE)
  fi

  PREV_COUNT=$(sketchybar --query github.bell | jq -r .label.value)
  # For sound to play around with:
  # afplay /System/Library/Sounds/Morse.aiff

  args+=(--remove '/github.notification\.*/')

  COUNTER=0
  COLOR=$GITHUB_BELL_DEFAULT
  args+=(--set github.bell icon.color=$COLOR)

  while read -r repo url type title
  do
    COUNTER=$((COUNTER + 1))
    # Limit to 10 notifications
    if [ $COUNTER -gt 10 ]; then
      break
    fi
    IMPORTANT="$(echo "$title" | egrep -i "(deprecat|break|broke)")"
    COLOR=$CONTENT_SECONDARY
    PADDING=0

    if [ "${repo}" = "" ] && [ "${title}" = "" ]; then
      repo="Note"
      title="No new notifications"
    fi
    case "${type}" in
      "'Issue'") COLOR=$GITHUB_ISSUE; ICON=$GIT_ISSUE; URL="$(gh api "$(echo "${url}" | sed -e "s/^'//" -e "s/'$//")" | jq .html_url)"
      ;;
      "'Discussion'") COLOR=$GITHUB_DISCUSSION; ICON=$GIT_DISCUSSION; URL="https://www.github.com/notifications"
      ;;
      "'PullRequest'") COLOR=$GITHUB_PULLREQUEST; ICON=$GIT_PULL_REQUEST; URL="$(gh api "$(echo "${url}" | sed -e "s/^'//" -e "s/'$//")" | jq .html_url)"
      ;;
      "'Commit'") COLOR=$GITHUB_COMMIT; ICON=$GIT_COMMIT; URL="$(gh api "$(echo "${url}" | sed -e "s/^'//" -e "s/'$//")" | jq .html_url)"
      ;;
    esac

    if [ "$IMPORTANT" != "" ]; then
      COLOR=$GITHUB_IMPORTANT
      ICON=􀁞
      args+=(--set github.bell icon.color=$COLOR)
    fi

    args+=(--clone github.notification.$COUNTER github.template \
           --set github.notification.$COUNTER label="$(echo "$title" | sed -e "s/^'//" -e "s/'$//")" \
                                            icon="$ICON $(echo "$repo" | sed -e "s/^'//" -e "s/'$//"):" \
                                            icon.padding_left="$PADDING" \
                                            label.padding_right="$PADDING" \
                                            icon.color=$COLOR \
                                            position=popup.github.bell \
                                            icon.background.color=$COLOR \
                                            drawing=on \
                                            click_script="open $URL;
                                                          sketchybar --set github.bell popup.drawing=off")
  done <<< "$(echo "$NOTIFICATIONS" | jq -r '.[] | [.repository.name, .subject.latest_comment_url, .subject.type, .subject.title] | @sh')"

  sketchybar -m "${args[@]}"

  if [ $COUNT -gt $PREV_COUNT ] 2>/dev/null || [ "$SENDER" = "forced" ]; then
    sketchybar --animate tanh 15 --set github.bell label.y_offset=5 label.y_offset=0
  fi
}

popup() {
  sketchybar --set $NAME popup.drawing=$1
}

case "$SENDER" in
  "routine"|"forced") update
  ;;
  "mouse.entered") popup on
  ;;
  "mouse.exited"|"mouse.exited.global") popup off
  ;;
  "mouse.clicked") popup toggle
  ;;
esac
