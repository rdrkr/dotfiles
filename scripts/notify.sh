#!/bin/bash
# Generic notification script for macOS using alerter.
# Handles tmux session/window context and click-to-focus.
#
# Usage:
#   notify.sh -title "Title" -message "Body" [options]
#   Works as a hook: echo '{"cwd":"..."}' | notify.sh -title "Claude"

set -euo pipefail

# --- Defaults ---
TITLE="Notification"
MESSAGE=""
SUBTITLE=""
APP_ICON=""
SOUND="default"
GROUP="claude-code"
EXTRA_ARGS=()

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --title) TITLE="$2"; shift 2 ;;
        --message) MESSAGE="$2"; shift 2 ;;
        --subtitle) SUBTITLE="$2"; shift 2 ;;
        --app-icon) APP_ICON="${2/#\~/$HOME}"; shift 2 ;; # Expand ~
        --sound) SOUND="$2"; shift 2 ;;
        --group) GROUP="$2"; shift 2 ;;
        *) EXTRA_ARGS+=("$1"); shift ;;
    esac
done

echo "[$(date)] Starting notify.sh with title: $TITLE" >> /tmp/claude_notify_trace.log

# Read hook JSON from stdin (Claude/Gemini pipe event data here)
INPUT=""
if [ ! -t 0 ]; then
    INPUT=$(cat 2>/dev/null || echo "")
fi

# Find alerter
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin"
ALERTER_BIN=$(command -v alerter || echo "")
if [ -z "$ALERTER_BIN" ]; then
    echo "[$(date)] ERROR: alerter not found in PATH" >> /tmp/claude_notify_trace.log
    exit 1
fi

# --- Skip notification if user is already viewing this session ---
if [ "${DEBUG_NOTIFY:-0}" != "1" ] && [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    SESSION_ATTACHED=$(tmux display-message -t "$TMUX_PANE" -p '#{session_attached}' 2>/dev/null || echo "0")
    PANE_ACTIVE=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_active}' 2>/dev/null || echo "0")
    WINDOW_ACTIVE=$(tmux display-message -t "$TMUX_PANE" -p '#{window_active}' 2>/dev/null || echo "0")
    if [ "$SESSION_ATTACHED" != "0" ] && [ "$PANE_ACTIVE" = "1" ] && [ "$WINDOW_ACTIVE" = "1" ]; then
        FOCUS_EVENTS=$(tmux show-options -s focus-events 2>/dev/null | grep -q 'on$' && echo "1" || echo "0")
        if [ "$FOCUS_EVENTS" = "0" ]; then
            FOCUS_EVENTS=$(tmux show-options -g focus-events 2>/dev/null | grep -q 'on$' && echo "1" || echo "0")
        fi

        if [ "$FOCUS_EVENTS" = "1" ]; then
            CLIENTS_FOCUSED=$(tmux list-clients -t "$TMUX_PANE" -F '#{client_flags}' 2>/dev/null | grep -c "focused" || true)
            if [ "${CLIENTS_FOCUSED:-0}" -gt "0" ]; then
                echo "[$(date)] SKIPPED: tmux client is focused" >> /tmp/claude_notify_trace.log
                exit 0
            fi
        else
            FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || echo "")
            FRONTMOST_LOWER=$(echo "$FRONTMOST" | tr '[:upper:]' '[:lower:]')
            case "$FRONTMOST_LOWER" in
                terminal|iterm2|alacritty|kitty|wezterm|ghostty) 
                    echo "[$(date)] SKIPPED: terminal app is frontmost (focus-events off)" >> /tmp/claude_notify_trace.log
                    exit 0 
                    ;;
            esac
        fi
    fi
fi

echo "[$(date)] NOT SKIPPED: User is not looking at the session." >> /tmp/claude_notify_trace.log

# --- tmux context (session, window, etc.) ---
TMUX_INFO=""
SESSION=""
WIN_INDEX=""
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    SESSION=$(tmux display-message -t "$TMUX_PANE" -p '#S' 2>/dev/null || echo "")
    WIN_INDEX=$(tmux display-message -t "$TMUX_PANE" -p '#I' 2>/dev/null || echo "")
    WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#W' 2>/dev/null || echo "")
    if [ -n "$SESSION" ]; then
        TMUX_INFO="${SESSION}"
        [ -n "$WIN_INDEX" ] && [ -n "$WINDOW" ] && TMUX_INFO="${TMUX_INFO} w${WIN_INDEX} > ${WINDOW}"
    fi
fi

# --- Click-to-focus: Terminal Bundle ID ---
TERM_BUNDLE_ID="${__CFBundleIdentifier:-}"
if [ -z "$TERM_BUNDLE_ID" ]; then
    TERM_PROG="${TERM_PROGRAM:-}"
    if [ "$TERM_PROG" = "tmux" ] && [ -n "${TMUX:-}" ]; then
        TERM_PROG=$(tmux show-environment TERM_PROGRAM 2>/dev/null | sed 's/^TERM_PROGRAM=//' || echo "")
    fi
    case "$TERM_PROG" in
        Apple_Terminal) TERM_BUNDLE_ID="com.apple.Terminal" ;;
        iTerm.app)     TERM_BUNDLE_ID="com.googlecode.iterm2" ;;
        ghostty)       TERM_BUNDLE_ID="com.mitchellh.ghostty" ;;
        Alacritty)     TERM_BUNDLE_ID="org.alacritty" ;;
        WezTerm)       TERM_BUNDLE_ID="com.github.wez.wezterm" ;;
        kitty)         TERM_BUNDLE_ID="net.kovidgoyal.kitty" ;;
    esac
fi

# --- Click-to-focus: Specific Terminal PID ---
TERM_PID=""
TARGET_CLIENT=""
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] && [ -n "$SESSION" ]; then
    CLIENT_LIST=$(tmux list-clients -F '#{client_activity}|#{client_pid}|#{client_tty}|#{client_name}|#{client_session}' 2>/dev/null || echo "")
    MATCH=$(echo "$CLIENT_LIST" | grep "|${SESSION}$" | sort -nr | head -n 1 || echo "")
    [ -z "$MATCH" ] && MATCH=$(echo "$CLIENT_LIST" | sort -nr | head -n 1 || echo "")

    if [ -n "$MATCH" ]; then
        CPID=$(echo "$MATCH" | cut -d'|' -f2)
        CTTY=$(echo "$MATCH" | cut -d'|' -f3 | sed 's|^/dev/||; s|^tty||')
        TARGET_CLIENT=$(echo "$MATCH" | cut -d'|' -f4)
        TERM_PID=$(ps -t "$CTTY" -o ppid= 2>/dev/null | head -n 1 | xargs || echo "")
        if [ -z "$TERM_PID" ] || [ "$TERM_PID" -le 1 ]; then
            CUR_PID="$CPID"
            while [ -n "$CUR_PID" ] && [ "$CUR_PID" -gt 1 ]; do
                INFO=$(ps -p "$CUR_PID" -o ppid= -o comm= 2>/dev/null || echo "")
                [ -z "$INFO" ] && break
                PARENT_PID=$(echo "$INFO" | awk '{print $1}')
                COMM=$(echo "$INFO" | awk '{print $2}')
                case "$COMM" in
                    *Ghostty*|*Terminal.app*|*iTerm2*|*Alacritty*|*kitty*|*wezterm*|*ghostty*)
                        TERM_PID="$CUR_PID"; break ;;
                esac
                CUR_PID="$PARENT_PID"
            done
        fi
    fi
fi

# Build click command
CLICK_CMD=""
if [ -n "$TERM_PID" ]; then
    CLICK_CMD="/usr/bin/osascript -e 'tell application \"System Events\"
        try
            set p to first process whose unix id is ${TERM_PID}
            set frontmost of p to true
            try
                repeat with w in windows of p
                    if name of w contains \"${SESSION}\" then
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

if [ -n "$CLICK_CMD" ]; then
    TMUX_BIN=$(command -v tmux 2>/dev/null || echo "")
    if [ -n "$TMUX_BIN" ] && [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] && [ -n "${SESSION:-}" ] && [ -n "${WIN_INDEX:-}" ]; then
        T_OPT=""
        [ -n "$TARGET_CLIENT" ] && T_OPT="-c '${TARGET_CLIENT}'"
        CLICK_CMD="${CLICK_CMD} && '${TMUX_BIN}' switch-client ${T_OPT} -t '${SESSION}' && '${TMUX_BIN}' select-window -t '${SESSION}:${WIN_INDEX}' && '${TMUX_BIN}' select-pane -t '${TMUX_PANE}'"
    fi
fi

# --- Project Name & Subtitle ---
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
PROJECT=""
[ -n "$CWD" ] && PROJECT=$(basename "$CWD")

FINAL_SUBTITLE="$SUBTITLE"
if [ -n "$TMUX_INFO" ] && [ -n "$PROJECT" ]; then
    CTX="${TMUX_INFO} · ${PROJECT}"
elif [ -n "$TMUX_INFO" ]; then
    CTX="${TMUX_INFO}"
elif [ -n "$PROJECT" ]; then
    CTX="${PROJECT}"
else
    CTX=""
fi

if [ -n "$FINAL_SUBTITLE" ] && [ -n "$CTX" ]; then
    FINAL_SUBTITLE="${FINAL_SUBTITLE} (${CTX})"
elif [ -z "$FINAL_SUBTITLE" ]; then
    FINAL_SUBTITLE="$CTX"
fi

# --- Alerter Notification ---
ALERTER_CMD=("$ALERTER_BIN" "--title" "$TITLE" "--message" "$MESSAGE" "--group" "$GROUP")
[ -n "$FINAL_SUBTITLE" ] && ALERTER_CMD+=("--subtitle" "$FINAL_SUBTITLE")
[ -n "$APP_ICON" ] && ALERTER_CMD+=("--app-icon" "$APP_ICON")
[ -n "$SOUND" ] && ALERTER_CMD+=("--sound" "$SOUND")
[ ${#EXTRA_ARGS[@]} -gt 0 ] && ALERTER_CMD+=("${EXTRA_ARGS[@]}")

# Execute alerter and wait for interaction in the background so we don't block the caller (Claude/Gemini)
(
    RESULT=$("${ALERTER_CMD[@]}" 2>/dev/null || echo "@ERROR")

    if [[ "$RESULT" == "@CONTENTCLICKED" || "$RESULT" == "@ACTIONClicked" ]]; then
        if [ -n "$CLICK_CMD" ]; then
            eval "$CLICK_CMD"
        fi
    fi
) </dev/null >/dev/null 2>&1 &
disown
