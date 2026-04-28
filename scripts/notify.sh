#!/bin/bash
# Copyright (c) 2026 by Ronen Druker.
#
# Generic macOS, Linux, and Windows notification script.
# Uses alerter on macOS, notify-send on Linux, and PowerShell on Windows/WSL.
# Sends native notifications with tmux session/window context and click-to-focus (macOS).
#
# Usage:
#   notify.sh [options]
#
# Options (mirrors alerter's interface):
#   --title <title>           Notification title (default: "Notification")
#   --subtitle <subtitle>     Notification subtitle
#   --message <message>       Notification message (default: "")
#   --sound <sound>           Sound name (default: "default")
#   --app-icon <path>         Path to icon image
#   --sender <bundle-id>      Bundle ID to impersonate
#   --group <group-id>        Group ID for notification replacement
#   --timeout <seconds>       Auto-close after N seconds (default: 0)
#   --actions <actions>       Comma-separated list of actions
#   --dropdown-label <label>  Label for the actions dropdown
#   --close-label <label>     Close button label
#   --reply <placeholder>     Display as reply-type alert
#   --content-image <path>    Image attached to notification
#   --json                    Output result as JSON
#   --ignore-dnd              Send even if DND is enabled
#   --skip-tmux-check         Skip the tmux active-pane suppression check
#   --completions <shell>     Output shell completions (bash, zsh, fish)
#   -h, --help                Show this help message
#
# Environment:
#   NOTIFY_ALERTER_BIN        Override alerter binary path
#
# When run inside tmux, the notification subtitle is enriched with
# session/window context and clicking the notification focuses the
# correct terminal window and pane.

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly DEFAULT_TITLE="Notification"
readonly DEFAULT_SOUND="default"
readonly DEFAULT_TIMEOUT="0"

# OS Detection
OS="$(uname -s)"
case "$OS" in
  Linux*)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      OS_TYPE="WSL"
    else
      OS_TYPE="Linux"
    fi
    ;;
  Darwin*)    OS_TYPE="macOS" ;;
  CYGWIN*|MINGW*|MSYS*) OS_TYPE="Windows" ;;
  *)          OS_TYPE="Unknown" ;;
esac

# All options with a value argument
readonly OPTIONS_WITH_VALUE=(
  --title --subtitle --message --sound --app-icon --sender --group
  --timeout --actions --dropdown-label --close-label --reply
  --content-image
)
# Boolean flags (no value argument)
readonly OPTIONS_BOOLEAN=(--json --ignore-dnd --skip-tmux-check)

# =============================================================================
# Help & completions
# =============================================================================

## show_help - Prints usage information and exits.
show_help() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Send macOS, Linux, or Windows notifications with tmux context.
Uses alerter on macOS, notify-send on Linux, and PowerShell on Windows.

Options:
  --title <title>             Notification title (default: "${DEFAULT_TITLE}")
  --subtitle <subtitle>       Notification subtitle
  --message <message>         Notification message
  --sound <sound>             Sound name (default: "${DEFAULT_SOUND}")
  --app-icon <path>           Path to icon image
  --sender <bundle-id>        Bundle ID to impersonate
  --group <group-id>          Group ID for notification replacement
  --timeout <seconds>         Auto-close after N seconds (default: ${DEFAULT_TIMEOUT})
  --actions <actions>         Comma-separated list of actions
  --dropdown-label <label>    Label for the actions dropdown
  --close-label <label>       Close button label
  --reply <placeholder>       Display as reply-type alert
  --content-image <path>      Image attached to notification
  --json                      Output result as JSON
  --ignore-dnd                Send even if Do Not Disturb is enabled
  --skip-tmux-check           Skip the tmux active-pane suppression check

  --completions <shell>       Output shell completions (bash, zsh, fish)
  -h, --help                  Show this help message

Environment:
  NOTIFY_ALERTER_BIN          Override alerter binary path

When run inside tmux, the subtitle is enriched with session/window
context and clicking the notification focuses the correct pane.

Shell completions:
  eval "\$(notify.sh --completions bash)"     # bash
  eval "\$(notify.sh --completions zsh)"      # zsh
  notify.sh --completions fish | source      # fish
EOF
  exit 0
}

## generate_completions - Outputs shell completion script for the given shell.
## Supported shells: bash, zsh, fish.
generate_completions() {
  local shell="$1"
  case "$shell" in
  bash)
    cat <<'BASH_COMP'
# bash completion for notify.sh
_notify_sh() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="--title --subtitle --message --sound --app-icon --sender --group --timeout --actions --dropdown-label --close-label --reply --content-image --json --ignore-dnd --skip-tmux-check --completions --help"

    case "$prev" in
        --sound)
            local sounds=""
            if [ -d /System/Library/Sounds ]; then
                sounds=$(find /System/Library/Sounds -name '*.aiff' -exec basename {} .aiff \; 2>/dev/null)
            fi
            COMPREPLY=($(compgen -W "$sounds" -- "$cur"))
            return 0
            ;;
        --app-icon|--content-image)
            COMPREPLY=($(compgen -f -- "$cur"))
            return 0
            ;;
        --completions)
            COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
            return 0
            ;;
    esac

    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
    return 0
}
complete -F _notify_sh notify.sh
BASH_COMP
    ;;
  zsh)
    cat <<'ZSH_COMP'
#compdef notify.sh
# zsh completion for notify.sh
_notify_sh() {
    local -a sounds
    if [ -d /System/Library/Sounds ]; then
        sounds=(${(f)"$(find /System/Library/Sounds -name '*.aiff' -exec basename {} .aiff \; 2>/dev/null)"})
    else
        sounds=()
    fi

    _arguments -s \
        '--title[Notification title]:title:' \
        '--subtitle[Notification subtitle]:subtitle:' \
        '--message[Notification message]:message:' \
        '--sound[Sound name]:sound:('$sounds')' \
        '--app-icon[Path to icon image]:icon:_files' \
        '--sender[Bundle ID to impersonate]:bundle-id:' \
        '--group[Group ID for replacement]:group-id:' \
        '--timeout[Auto-close after N seconds]:seconds:' \
        '--actions[Comma-separated actions]:actions:' \
        '--dropdown-label[Label for actions dropdown]:label:' \
        '--close-label[Close button label]:label:' \
        '--reply[Reply placeholder text]:placeholder:' \
        '--content-image[Image attached to notification]:image:_files' \
        '--json[Output result as JSON]' \
        '--ignore-dnd[Send even if DND is enabled]' \
        '--skip-tmux-check[Skip tmux suppression check]' \
        '--completions[Output shell completions]:shell:(bash zsh fish)' \
        '(-h --help)'{-h,--help}'[Show help message]'
}
compdef _notify_sh notify.sh
ZSH_COMP
    ;;
  fish)
    cat <<'FISH_COMP'
# fish completion for notify.sh
complete -c notify.sh -l title -d 'Notification title' -x
complete -c notify.sh -l subtitle -d 'Notification subtitle' -x
complete -c notify.sh -l message -d 'Notification message' -x
complete -c notify.sh -l sound -d 'Sound name' -x -a '(find /System/Library/Sounds -name "*.aiff" -exec basename {} .aiff \; 2>/dev/null)'
complete -c notify.sh -l app-icon -d 'Path to icon image' -r -F
complete -c notify.sh -l sender -d 'Bundle ID to impersonate' -x
complete -c notify.sh -l group -d 'Group ID for replacement' -x
complete -c notify.sh -l timeout -d 'Auto-close after N seconds' -x
complete -c notify.sh -l actions -d 'Comma-separated actions' -x
complete -c notify.sh -l dropdown-label -d 'Label for actions dropdown' -x
complete -c notify.sh -l close-label -d 'Close button label' -x
complete -c notify.sh -l reply -d 'Reply placeholder text' -x
complete -c notify.sh -l content-image -d 'Image attached to notification' -r -F
complete -c notify.sh -l json -d 'Output result as JSON'
complete -c notify.sh -l ignore-dnd -d 'Send even if DND is enabled'
complete -c notify.sh -l skip-tmux-check -d 'Skip tmux suppression check'
complete -c notify.sh -l completions -d 'Output shell completions' -x -a 'bash zsh fish'
complete -c notify.sh -s h -l help -d 'Show help message'
FISH_COMP
    ;;
  *)
    echo "notify.sh: unsupported shell: $shell (use bash, zsh, or fish)" >&2
    exit 1
    ;;
  esac
  exit 0
}

# =============================================================================
# Argument parsing
# =============================================================================

# Defaults
ARG_TITLE="$DEFAULT_TITLE"
ARG_SUBTITLE=""
ARG_MESSAGE=""
ARG_SOUND="$DEFAULT_SOUND"
ARG_APP_ICON=""
ARG_SENDER=""
ARG_GROUP=""
ARG_TIMEOUT="$DEFAULT_TIMEOUT"
ARG_ACTIONS=""
ARG_DROPDOWN_LABEL=""
ARG_CLOSE_LABEL=""
ARG_REPLY=""
ARG_CONTENT_IMAGE=""
ARG_JSON=""
ARG_IGNORE_DND=""
ARG_SKIP_TMUX_CHECK=""

## parse_args - Parses command-line arguments into ARG_* variables.
## Supports the same option names as alerter plus --skip-tmux-check.
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
    --title)
      ARG_TITLE="${2:-}"
      shift 2
      ;;
    --subtitle)
      ARG_SUBTITLE="${2:-}"
      shift 2
      ;;
    --message)
      ARG_MESSAGE="${2:-}"
      shift 2
      ;;
    --sound)
      ARG_SOUND="${2:-}"
      shift 2
      ;;
    --app-icon)
      ARG_APP_ICON="${2:-}"
      shift 2
      ;;
    --sender)
      ARG_SENDER="${2:-}"
      shift 2
      ;;
    --group)
      ARG_GROUP="${2:-}"
      shift 2
      ;;
    --timeout)
      ARG_TIMEOUT="${2:-}"
      shift 2
      ;;
    --actions)
      ARG_ACTIONS="${2:-}"
      shift 2
      ;;
    --dropdown-label)
      ARG_DROPDOWN_LABEL="${2:-}"
      shift 2
      ;;
    --close-label)
      ARG_CLOSE_LABEL="${2:-}"
      shift 2
      ;;
    --reply)
      ARG_REPLY="${2:-}"
      shift 2
      ;;
    --content-image)
      ARG_CONTENT_IMAGE="${2:-}"
      shift 2
      ;;
    --json)
      ARG_JSON="1"
      shift
      ;;
    --ignore-dnd)
      ARG_IGNORE_DND="1"
      shift
      ;;
    --skip-tmux-check)
      ARG_SKIP_TMUX_CHECK="1"
      shift
      ;;
    -h | --help) show_help ;;
    --completions)
      generate_completions "${2:-}"
      shift 2
      ;;
    *)
      echo "notify.sh: unknown option: $1" >&2
      shift
      ;;
    esac
  done
}

# =============================================================================
# Tmux & terminal detection
# =============================================================================

## should_suppress_notification - Determines if the user is currently viewing
## the tmux pane that triggered the notification. Returns 0 (true) if the
## notification should be suppressed, 1 (false) otherwise.
## Uses focus-events when available for accurate multi-instance detection,
## falls back to osascript frontmost-app check.
should_suppress_notification() {
  [ -n "$ARG_SKIP_TMUX_CHECK" ] && return 1

  # Only applies inside tmux
  [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ] && return 1

  local session_attached pane_active window_active
  session_attached=$(tmux display-message -t "$TMUX_PANE" -p '#{session_attached}' 2>/dev/null || echo "0")
  pane_active=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_active}' 2>/dev/null || echo "0")
  window_active=$(tmux display-message -t "$TMUX_PANE" -p '#{window_active}' 2>/dev/null || echo "0")

  # Not attached or not the active pane/window — don't suppress
  [ "$session_attached" = "0" ] || [ "$pane_active" != "1" ] || [ "$window_active" != "1" ] && return 1

  # Check if focus-events is enabled (server or global option)
  local focus_events="0"
  if tmux show-options -s focus-events 2>/dev/null | grep -q 'on$'; then
    focus_events="1"
  elif tmux show-options -g focus-events 2>/dev/null | grep -q 'on$'; then
    focus_events="1"
  fi

  if [ "$focus_events" = "1" ]; then
    # Accurate: check if any client viewing this pane is focused
    local clients_focused
    clients_focused=$(tmux list-clients -t "$TMUX_PANE" -F '#{client_flags}' 2>/dev/null | grep -c "focused" || true)
    [ "${clients_focused:-0}" -gt "0" ] && return 0
    # focus-events on but no focused client — user is NOT looking, don't suppress
    return 1
  else
    # Fallback: check if a terminal app is frontmost (less accurate with multiple instances)
    if [ "$OS_TYPE" = "macOS" ]; then
      local frontmost frontmost_lower
      frontmost=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || echo "")
      frontmost_lower=$(echo "$frontmost" | tr '[:upper:]' '[:lower:]')
      case "$frontmost_lower" in
      terminal | iterm2 | alacritty | kitty | wezterm | ghostty) return 0 ;;
      esac
    fi
  fi

  return 1
}

## get_tmux_context - Populates TMUX_SESSION, TMUX_WIN_INDEX, TMUX_WINDOW,
## and TMUX_INFO with the current tmux session/window context.
get_tmux_context() {
  TMUX_SESSION=""
  TMUX_WIN_INDEX=""
  TMUX_WINDOW=""
  TMUX_INFO=""

  [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ] && return

  TMUX_SESSION=$(tmux display-message -t "$TMUX_PANE" -p '#S' 2>/dev/null || echo "")
  TMUX_WIN_INDEX=$(tmux display-message -t "$TMUX_PANE" -p '#I' 2>/dev/null || echo "")
  TMUX_WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#W' 2>/dev/null || echo "")

  if [ -n "$TMUX_SESSION" ]; then
    TMUX_INFO="$TMUX_SESSION"
    if [ -n "$TMUX_WIN_INDEX" ] && [ -n "$TMUX_WINDOW" ]; then
      TMUX_INFO="${TMUX_INFO} w${TMUX_WIN_INDEX} > ${TMUX_WINDOW}"
    elif [ -n "$TMUX_WINDOW" ]; then
      TMUX_INFO="${TMUX_INFO} > ${TMUX_WINDOW}"
    fi
  fi
}

## get_terminal_bundle_id - Detects the terminal emulator's macOS bundle ID.
## Sets TERM_BUNDLE_ID. Uses __CFBundleIdentifier if available, otherwise
## maps TERM_PROGRAM (resolving through tmux if needed).
get_terminal_bundle_id() {
  TERM_BUNDLE_ID="${__CFBundleIdentifier:-}"
  if [ "$OS_TYPE" != "macOS" ]; then
    return
  fi
  if [ -z "$TERM_BUNDLE_ID" ]; then
    local term_prog="${TERM_PROGRAM:-}"
    if [ "$term_prog" = "tmux" ] && [ -n "${TMUX:-}" ]; then
      term_prog=$(tmux show-environment TERM_PROGRAM 2>/dev/null | sed 's/^TERM_PROGRAM=//' || echo "")
    fi
    case "$term_prog" in
    Apple_Terminal) TERM_BUNDLE_ID="com.apple.Terminal" ;;
    iTerm.app) TERM_BUNDLE_ID="com.googlecode.iterm2" ;;
    ghostty) TERM_BUNDLE_ID="com.mitchellh.ghostty" ;;
    Alacritty) TERM_BUNDLE_ID="org.alacritty" ;;
    WezTerm) TERM_BUNDLE_ID="com.github.wez.wezterm" ;;
    kitty) TERM_BUNDLE_ID="net.kovidgoyal.kitty" ;;
    esac
  fi
}

## get_terminal_pid - Finds the PID of the terminal emulator process attached
## to the current tmux session. Sets TERM_PID and TARGET_CLIENT.
## Tries ps -t on the client TTY first, then walks the process tree.
get_terminal_pid() {
  TERM_PID=""
  TARGET_CLIENT=""

  [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ] && return

  # Format: activity|pid|tty|name|session
  local client_list match cpid ctty
  client_list=$(tmux list-clients -F '#{client_activity}|#{client_pid}|#{client_tty}|#{client_name}|#{client_session}' 2>/dev/null || echo "")

  # Prefer client in target session (most recently active)
  match=$(echo "$client_list" | grep "|${TMUX_SESSION}$" | sort -nr | head -n 1 || echo "")

  # Fallback: any client
  if [ -z "$match" ]; then
    match=$(echo "$client_list" | sort -nr | head -n 1 || echo "")
  fi

  [ -z "$match" ] && return

  cpid=$(echo "$match" | cut -d'|' -f2)
  ctty=$(echo "$match" | cut -d'|' -f3 | sed 's|^/dev/||; s|^tty||')
  TARGET_CLIENT=$(echo "$match" | cut -d'|' -f4)

  # Method A: ps -t to find parent of process on that TTY
  TERM_PID=$(ps -t "$ctty" -o ppid= 2>/dev/null | head -n 1 | xargs || echo "")

  # Method B: walk process tree from tmux client PID
  if [ -z "$TERM_PID" ] || [ "$TERM_PID" -le 1 ]; then
    local cur_pid="$cpid"
    while [ -n "$cur_pid" ] && [ "$cur_pid" -gt 1 ]; do
      local info parent_pid comm
      info=$(ps -p "$cur_pid" -o ppid= -o comm= 2>/dev/null || echo "")
      [ -z "$info" ] && break
      parent_pid=$(echo "$info" | awk '{print $1}')
      comm=$(echo "$info" | awk '{print $2}')
      case "$comm" in
      *Ghostty* | *Terminal.app* | *iTerm2* | *Alacritty* | *kitty* | *wezterm* | *ghostty*)
        TERM_PID="$cur_pid"
        break
        ;;
      esac
      cur_pid="$parent_pid"
    done
  fi
}

## build_click_command - Constructs a shell command string that, when executed,
## focuses the correct terminal window and switches to the right tmux pane.
## Sets CLICK_CMD.
build_click_command() {
  CLICK_CMD=""

  if [ "$OS_TYPE" = "macOS" ]; then
    if [ -n "$TERM_PID" ]; then
      CLICK_CMD="/usr/bin/osascript -e 'tell application \"System Events\"
          try
              set p to first process whose unix id is ${TERM_PID}
              set frontmost of p to true
              try
                  repeat with w in windows of p
                      if name of w contains \"${TMUX_SESSION}\" then
                          perform action \"AXRaise\" of w
                          exit repeat
                      end if
                  end repeat
              end try
          end try
      end tell'"
    fi

    if [ -n "$TERM_BUNDLE_ID" ]; then
      if [ -n "$CLICK_CMD" ]; then
        CLICK_CMD="${CLICK_CMD} || /usr/bin/open -b '${TERM_BUNDLE_ID}'"
      else
        CLICK_CMD="/usr/bin/open -b '${TERM_BUNDLE_ID}'"
      fi
    fi
  fi

  local tmux_bin
  tmux_bin=$(command -v tmux 2>/dev/null || echo "")
  if [ -n "$tmux_bin" ] && [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] && [ -n "${TMUX_SESSION:-}" ] && [ -n "${TMUX_WIN_INDEX:-}" ]; then
    local t_cmd="'${tmux_bin}' switch-client"
    [ -n "$TARGET_CLIENT" ] && t_cmd="${t_cmd} -c '${TARGET_CLIENT}'"
    t_cmd="${t_cmd} -t '${TMUX_SESSION}' && '${tmux_bin}' select-window -t '${TMUX_SESSION}:${TMUX_WIN_INDEX}' && '${tmux_bin}' select-pane -t '${TMUX_PANE}'"
    
    if [ -n "$CLICK_CMD" ]; then
      CLICK_CMD="${CLICK_CMD} && ${t_cmd}"
    else
      CLICK_CMD="${t_cmd}"
    fi
  fi
}

# =============================================================================
# Subtitle enrichment
# =============================================================================

## build_subtitle - Enriches the notification subtitle with tmux context and
## project name from stdin JSON (if available). Sets SUBTITLE.
## If --subtitle was provided, it is combined with tmux context.
build_subtitle() {
  local project=""

  # Try to extract project name from hook JSON on stdin
  if [ -n "${HOOK_INPUT:-}" ]; then
    local cwd
    cwd=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
    [ -n "$cwd" ] && project=$(basename "$cwd")
  fi

  SUBTITLE="$ARG_SUBTITLE"

  # Build context string from tmux info and project
  local context=""
  if [ -n "$TMUX_INFO" ] && [ -n "$project" ]; then
    context="${TMUX_INFO} · ${project}"
  elif [ -n "$TMUX_INFO" ]; then
    context="$TMUX_INFO"
  elif [ -n "$project" ]; then
    context="$project"
  fi

  # Combine: user subtitle takes priority, context is appended
  if [ -n "$SUBTITLE" ] && [ -n "$context" ]; then
    SUBTITLE="${SUBTITLE} — ${context}"
  elif [ -n "$context" ]; then
    SUBTITLE="$context"
  fi
}

# =============================================================================
# Notification dispatch
# =============================================================================

## run_alerter_worker - Background worker entry point. Invoked via
## __worker to run alerter (which blocks until the user interacts with the
## notification). When the user clicks the "Open" action, executes the
## click-to-focus command passed via _NOTIFY_CLICK_CMD env var.
## This pattern is necessary because alerter blocks — unlike terminal-notifier's
## -execute flag, alerter outputs the clicked action to stdout and we must
## wait for it, then act on the result.
## All notification parameters are passed as individual _NOTIFY_* env vars
## (bash cannot store NUL bytes, so array serialization is not reliable).
run_alerter_worker() {
  local alerter_bin="${_NOTIFY_ALERTER_BIN:-$(command -v alerter 2>/dev/null || echo "")}"
  [ -z "$alerter_bin" ] || [ ! -x "$alerter_bin" ] && exit 1

  # Use provided group or generate a unique one if in tmux (for auto-dismissal)
  local group="${_NOTIFY_GROUP:-}"
  if [ -z "$group" ] && [ -n "${_NOTIFY_TMUX_PANE:-}" ]; then
    group="notify-pane-${_NOTIFY_TMUX_PANE//%/_}-$$"
  fi

  # Rebuild alerter args from individual env vars
  local -a args=(--title "${_NOTIFY_TITLE:-}" --message "${_NOTIFY_MESSAGE:-}")
  [ -n "${_NOTIFY_SUBTITLE:-}" ] && args+=(--subtitle "$_NOTIFY_SUBTITLE")
  [ -n "${_NOTIFY_SOUND:-}" ] && args+=(--sound "$_NOTIFY_SOUND")
  [ -n "${_NOTIFY_APP_ICON:-}" ] && args+=(--app-icon "$_NOTIFY_APP_ICON")
  [ -n "${_NOTIFY_SENDER:-}" ] && args+=(--sender "$_NOTIFY_SENDER")
  [ -n "$group" ] && args+=(--group "$group")
  [ -n "${_NOTIFY_TIMEOUT:-}" ] && [ "$_NOTIFY_TIMEOUT" != "0" ] && args+=(--timeout "$_NOTIFY_TIMEOUT")
  [ -n "${_NOTIFY_ACTIONS:-}" ] && args+=(--actions "$_NOTIFY_ACTIONS")
  [ -n "${_NOTIFY_DROPDOWN_LABEL:-}" ] && args+=(--dropdown-label "$_NOTIFY_DROPDOWN_LABEL")
  [ -n "${_NOTIFY_CLOSE_LABEL:-}" ] && args+=(--close-label "$_NOTIFY_CLOSE_LABEL")
  [ -n "${_NOTIFY_REPLY:-}" ] && args+=(--reply "$_NOTIFY_REPLY")
  [ -n "${_NOTIFY_CONTENT_IMAGE:-}" ] && args+=(--content-image "$_NOTIFY_CONTENT_IMAGE")
  [ "${_NOTIFY_JSON:-}" = "1" ] && args+=(--json)
  [ "${_NOTIFY_IGNORE_DND:-}" = "1" ] && args+=(--ignore-dnd)
  [ -n "${_NOTIFY_CLICK_CMD:-}" ] && args+=(--actions "Open")

  # Start a monitor process to dismiss the notification if the user manually focuses the pane
  local monitor_pid=""
  if [ -n "${_NOTIFY_TMUX_PANE:-}" ] && [ -n "$group" ] && [ "${_NOTIFY_SKIP_TMUX_CHECK:-0}" != "1" ]; then
    (
      export TMUX="${_NOTIFY_TMUX:-}"
      export TMUX_PANE="${_NOTIFY_TMUX_PANE:-}"
      export ARG_SKIP_TMUX_CHECK="${_NOTIFY_SKIP_TMUX_CHECK:-}"

      # Wait a moment before polling to let the notification appear
      sleep 1

      # Poll until the parent (run_alerter_worker) dies or we suppress
      while kill -0 $$ 2>/dev/null; do
        if should_suppress_notification; then
          "$alerter_bin" --remove "$group" 2>/dev/null || true
          break
        fi
        sleep 1
      done
    ) &
    monitor_pid=$!
  fi

  # Run alerter (blocks until user dismisses/clicks)
  local result
  result=$("$alerter_bin" "${args[@]}" 2>/dev/null) || true

  # Clean up monitor process
  if [ -n "$monitor_pid" ]; then
    kill "$monitor_pid" 2>/dev/null || true
  fi

  # If user clicked "Open" action, execute the click-to-focus command
  if [ -n "${_NOTIFY_CLICK_CMD:-}" ]; then
    case "$result" in
    @CONTENTCLICKED | @ACTIONCLICKED | Open)
      eval "$_NOTIFY_CLICK_CMD"
      ;;
    esac
  fi

  exit 0
}

## send_notification_alerter - Sends a notification using alerter in a
## background worker process (alerter blocks until the user interacts).
## Spawns a detached worker via self-invocation with __worker, passing
## all notification parameters as individual _NOTIFY_* env vars.
## Falls back to osascript if alerter is not found.
send_notification_alerter() {
  local alerter_bin="${NOTIFY_ALERTER_BIN:-$(command -v alerter 2>/dev/null || echo "")}"

  if [ -n "$alerter_bin" ] && [ -x "$alerter_bin" ]; then
    # Spawn detached worker: re-invoke this script with __worker,
    # passing all data via individual env vars to avoid quoting/NUL issues.
    env \
      _NOTIFY_ALERTER_BIN="$alerter_bin" \
      _NOTIFY_TITLE="$ARG_TITLE" \
      _NOTIFY_MESSAGE="$ARG_MESSAGE" \
      _NOTIFY_SUBTITLE="${SUBTITLE:-}" \
      _NOTIFY_SOUND="$ARG_SOUND" \
      _NOTIFY_APP_ICON="$ARG_APP_ICON" \
      _NOTIFY_SENDER="$ARG_SENDER" \
      _NOTIFY_GROUP="$ARG_GROUP" \
      _NOTIFY_TIMEOUT="$ARG_TIMEOUT" \
      _NOTIFY_ACTIONS="$ARG_ACTIONS" \
      _NOTIFY_DROPDOWN_LABEL="$ARG_DROPDOWN_LABEL" \
      _NOTIFY_CLOSE_LABEL="$ARG_CLOSE_LABEL" \
      _NOTIFY_REPLY="$ARG_REPLY" \
      _NOTIFY_CONTENT_IMAGE="$ARG_CONTENT_IMAGE" \
      _NOTIFY_JSON="$ARG_JSON" \
      _NOTIFY_IGNORE_DND="$ARG_IGNORE_DND" \
      _NOTIFY_CLICK_CMD="${CLICK_CMD:-}" \
      _NOTIFY_TMUX="${TMUX:-}" \
      _NOTIFY_TMUX_PANE="${TMUX_PANE:-}" \
      _NOTIFY_SKIP_TMUX_CHECK="${ARG_SKIP_TMUX_CHECK:-}" \
      nohup "$0" __worker >/dev/null 2>&1 </dev/null &
  else
    send_notification_osascript
  fi
}

## send_notification_osascript - Fallback notification using osascript.
## Shows Script Editor icon; no click-to-focus support.
send_notification_osascript() {
  local title_esc="${ARG_TITLE//\"/\\\"}"
  local body_esc="${ARG_MESSAGE//\"/\\\"}"
  local sound="${ARG_SOUND:-default}"

  if [ -n "$SUBTITLE" ]; then
    local sub_esc="${SUBTITLE//\"/\\\"}"
    osascript -e "display notification \"${body_esc}\" with title \"${title_esc}\" subtitle \"${sub_esc}\" sound name \"${sound}\""
  else
    osascript -e "display notification \"${body_esc}\" with title \"${title_esc}\" sound name \"${sound}\""
  fi
}

## send_notification_linux - Sends a notification using notify-send on Linux.
send_notification_linux() {
  local title="$ARG_TITLE"
  if [ -n "$SUBTITLE" ]; then
    title="$title - $SUBTITLE"
  fi
  local cmd=(notify-send)
  [ -n "$ARG_APP_ICON" ] && cmd+=(-i "$ARG_APP_ICON")
  [ -n "$ARG_TIMEOUT" ] && [ "$ARG_TIMEOUT" != "0" ] && cmd+=(-t "$((ARG_TIMEOUT * 1000))")
  cmd+=("$title" "$ARG_MESSAGE")
  
  "${cmd[@]}" 2>/dev/null || true
}

## send_notification_windows - Sends a notification using PowerShell on Windows/WSL.
send_notification_windows() {
  local title="$ARG_TITLE"
  if [ -n "$SUBTITLE" ]; then
    title="$title - $SUBTITLE"
  fi
  # Escape single quotes for PowerShell
  local safe_title="${title//\'/\'\'}"
  local safe_message="${ARG_MESSAGE//\'/\'\'}"
  
  if command -v powershell.exe >/dev/null; then
    local ps_script="
      \$ErrorActionPreference = 'Stop'
      try {
        if (Get-Module -ListAvailable -Name BurntToast) {
          New-BurntToastNotification -Text '$safe_title', '$safe_message'
        } else {
          [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
          [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
          \$xml = @\"
<toast><visual><binding template=\"ToastText02\"><text id=\"1\">$safe_title</text><text id=\"2\">$safe_message</text></binding></visual></toast>
\"@
          \$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
          \$doc.LoadXml(\$xml)
          \$toast = New-Object Windows.UI.Notifications.ToastNotification(\$doc)
          [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('PowerShell').Show(\$toast)
        }
      } catch {
        [reflection.assembly]::loadwithpartialname('System.Windows.Forms') | Out-Null
        \$notify = new-object system.windows.forms.notifyicon
        \$notify.icon = [System.Drawing.SystemIcons]::Information
        \$notify.visible = \$true
        \$notify.showballoontip(10000, '$safe_title', '$safe_message', [system.windows.forms.tooltipicon]::None)
        Start-Sleep -Seconds 3
        \$notify.Dispose()
      }
    "
    powershell.exe -NoProfile -Command "$ps_script" >/dev/null 2>&1 &
  fi
}

## play_sound - Plays the notification sound depending on the OS.
play_sound() {
  case "$OS_TYPE" in
    macOS)
      local sound_file="/System/Library/Sounds/${ARG_SOUND}.aiff"
      if [ -f "$sound_file" ]; then
        afplay "$sound_file" &
      fi
      ;;
    Linux)
      if command -v paplay >/dev/null; then
        paplay /usr/share/sounds/freedesktop/stereo/message.oga >/dev/null 2>&1 &
      elif command -v aplay >/dev/null; then
        aplay /usr/share/sounds/alsa/Front_Center.wav >/dev/null 2>&1 &
      fi
      ;;
    WSL|Windows)
      if command -v powershell.exe >/dev/null; then
        powershell.exe -NoProfile -Command "[System.Media.SystemSounds]::Asterisk.Play()" >/dev/null 2>&1 &
      fi
      ;;
  esac
}

# =============================================================================
# Main
# =============================================================================

## main - Entry point. Parses arguments, checks suppression, gathers tmux
## context, and dispatches the notification.
## When invoked with __worker as the first argument, runs the background
## alerter worker instead (used internally for click-to-focus support).
main() {
  # Internal: background worker mode for alerter click-to-focus
  if [ "${1:-}" = "__worker" ]; then
    run_alerter_worker
    return
  fi

  parse_args "$@"

  # Read hook JSON from stdin if available (Claude Code / Gemini pipe event data)
  HOOK_INPUT=""
  if [ ! -t 0 ]; then
    HOOK_INPUT=$(cat)
  fi

  # Check if we should suppress (user is looking at the pane)
  if should_suppress_notification; then
    exit 0
  fi

  # Gather tmux context
  get_tmux_context
  get_terminal_bundle_id
  get_terminal_pid
  build_click_command
  build_subtitle

  # Send notification based on OS
  case "$OS_TYPE" in
    macOS)
      send_notification_alerter
      ;;
    Linux)
      send_notification_linux
      ;;
    WSL|Windows)
      send_notification_windows
      ;;
    *)
      send_notification_linux
      ;;
  esac

  # Play sound via system audio
  play_sound
}

main "$@"