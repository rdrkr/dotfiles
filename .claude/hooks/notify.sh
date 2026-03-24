#!/bin/bash
# Claude Code notification hook for macOS
# Sends native notifications with tmux session/window context.
#
# Usage: Called by Claude Code hooks with JSON on stdin.
#   notify.sh needs_input   — Claude needs you to approve something
#   notify.sh done           — Claude finished and is idle

set -euo pipefail

NOTIFY_TYPE="${1:-done}"

# Read hook JSON from stdin (Claude Code pipes event data)
INPUT=$(cat)

# --- Skip notification if user is already viewing this session ---
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    SESSION_ATTACHED=$(tmux display-message -t "$TMUX_PANE" -p '#{session_attached}' 2>/dev/null || echo "0")
    PANE_ACTIVE=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_active}' 2>/dev/null || echo "0")
    WINDOW_ACTIVE=$(tmux display-message -t "$TMUX_PANE" -p '#{window_active}' 2>/dev/null || echo "0")
    if [ "$SESSION_ATTACHED" != "0" ] && [ "$PANE_ACTIVE" = "1" ] && [ "$WINDOW_ACTIVE" = "1" ]; then
        # Check if focus-events is enabled (could be server or global option depending on tmux version)
        FOCUS_EVENTS=$(tmux show-options -s focus-events 2>/dev/null | grep -q 'on$' && echo "1" || echo "0")
        if [ "$FOCUS_EVENTS" = "0" ]; then
            FOCUS_EVENTS=$(tmux show-options -g focus-events 2>/dev/null | grep -q 'on$' && echo "1" || echo "0")
        fi

        if [ "$FOCUS_EVENTS" = "1" ]; then
            # If focus-events is on, we can accurately determine if the specific tmux client is focused.
            # This solves the issue of multiple instances of the same terminal app.
            # (grep -c outputs "0" and exits 1 if no matches found, so we don't need '|| echo 0' here)
            CLIENTS_FOCUSED=$(tmux list-clients -t "$TMUX_PANE" -F '#{client_flags}' 2>/dev/null | grep -c "focused" || true)
            if [ "${CLIENTS_FOCUSED:-0}" -gt "0" ]; then
                exit 0 # Safe to skip notification, user is looking right at it
            fi
            # If focus-events is on but no client is focused, the user is NOT looking at it.
            # We should continue to send the notification, bypassing the inaccurate osascript check.
        else
            # Fallback for when focus-events is OFF.
            # This is less accurate and has the "multiple terminal instances" bug.
            FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || echo "")
            FRONTMOST_LOWER=$(echo "$FRONTMOST" | tr '[:upper:]' '[:lower:]')
            case "$FRONTMOST_LOWER" in
                terminal|iterm2|alacritty|kitty|wezterm|ghostty)
                    exit 0
                    ;;
            esac
        fi
    fi
fi

# --- Notification type ---
if [ "$NOTIFY_TYPE" = "needs_input" ]; then
    TITLE="Claude Code — Needs Input"
    BODY="Claude is waiting for your input"
    SOUND="Ping"
else
    TITLE="Claude Code — Done"
    BODY="Claude has finished and is awaiting further instructions"
    SOUND="Glass"
fi

# --- tmux context (session, window number, window name) ---
TMUX_INFO=""
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    SESSION=$(tmux display-message -t "$TMUX_PANE" -p '#S' 2>/dev/null || echo "")
    WIN_INDEX=$(tmux display-message -t "$TMUX_PANE" -p '#I' 2>/dev/null || echo "")
    WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#W' 2>/dev/null || echo "")
    if [ -n "$SESSION" ]; then
        TMUX_INFO="${SESSION}"
        if [ -n "$WIN_INDEX" ] && [ -n "$WINDOW" ]; then
            TMUX_INFO="${TMUX_INFO} w${WIN_INDEX} > ${WINDOW}"
        elif [ -n "$WINDOW" ]; then
            TMUX_INFO="${TMUX_INFO} > ${WINDOW}"
        fi
    fi
fi

# --- Click-to-focus: detect terminal bundle ID ---
# __CFBundleIdentifier is set by macOS for GUI apps — it's already the bundle ID.
# Falls back to mapping TERM_PROGRAM for non-GUI-launched terminals.
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

# --- Click-to-focus: find specific terminal PID ---
# Try to find the specific terminal process PID attached to the tmux session.
# This ensures that if multiple instances exist, we focus the correct one.
TERM_PID=""
TARGET_CLIENT=""
if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ]; then
    # 1. Find all clients and their terminal parents
    # Format: activity|pid|tty|name|session
    CLIENT_LIST=$(tmux list-clients -F '#{client_activity}|#{client_pid}|#{client_tty}|#{client_name}|#{client_session}' 2>/dev/null || echo "")

    # 2. Look for a client already in the target session (prefer most recently active)
    MATCH=$(echo "$CLIENT_LIST" | grep "|${SESSION}$" | sort -nr | head -n 1 || echo "")

    # 3. If no client in target session, look for ANY client (prefer most recently active)
    if [ -z "$MATCH" ]; then
        MATCH=$(echo "$CLIENT_LIST" | sort -nr | head -n 1 || echo "")
    fi

    if [ -n "$MATCH" ]; then
        CPID=$(echo "$MATCH" | cut -d'|' -f2)
        CTTY=$(echo "$MATCH" | cut -d'|' -f3 | sed 's|^/dev/||; s|^tty||')
        TARGET_CLIENT=$(echo "$MATCH" | cut -d'|' -f4)

        # Try to find the terminal emulator PID.
        # Method A: Use ps -t to find the parent of the process using that TTY (usually login or shell)
        TERM_PID=$(ps -t "$CTTY" -o ppid= 2>/dev/null | head -n 1 | xargs || echo "")

        # Method B: Fallback to walking up the process tree from the tmux client
        if [ -z "$TERM_PID" ] || [ "$TERM_PID" -le 1 ]; then
            CUR_PID="$CPID"
            while [ -n "$CUR_PID" ] && [ "$CUR_PID" -gt 1 ]; do
                INFO=$(ps -p "$CUR_PID" -o ppid= -o comm= 2>/dev/null || echo "")
                [ -z "$INFO" ] && break
                PARENT_PID=$(echo "$INFO" | awk '{print $1}')
                COMM=$(echo "$INFO" | awk '{print $2}')
                case "$COMM" in
                    *Ghostty*|*Terminal.app*|*iTerm2*|*Alacritty*|*kitty*|*wezterm*|*ghostty*)
                        TERM_PID="$CUR_PID"
                        break
                        ;;
                esac
                CUR_PID="$PARENT_PID"
            done
        fi
    fi
fi

# Build click command: activate terminal + switch to the correct tmux window/pane.
# Everything goes into -execute because -activate and -execute conflict in terminal-notifier.
# Full paths are required because terminal-notifier runs -execute via bare /bin/sh (no PATH).
CLICK_CMD=""
if [ -n "$TERM_PID" ]; then
    # Focus specific PID via AppleScript (precise for multiple instances/processes).
    # Also attempt to find the window containing the session name if it's a multi-window app.
    # The 'try' blocks handle cases where the PID or window properties aren't accessible.
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
        # Try PID focus, fall back to bundle activation.
        CLICK_CMD="${CLICK_CMD} || /usr/bin/open -b '${TERM_BUNDLE_ID}'"
    else
        CLICK_CMD="/usr/bin/open -b '${TERM_BUNDLE_ID}'"
    fi
fi

if [ -n "$CLICK_CMD" ]; then
    TMUX_BIN=$(command -v tmux 2>/dev/null || echo "")
    if [ -n "$TMUX_BIN" ] && [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] && [ -n "${SESSION:-}" ] && [ -n "${WIN_INDEX:-}" ]; then
        # Target the specific client we found to avoid switching sessions in the wrong window.
        T_OPT=""
        [ -n "$TARGET_CLIENT" ] && T_OPT="-c '${TARGET_CLIENT}'"
        CLICK_CMD="${CLICK_CMD} && '${TMUX_BIN}' switch-client ${T_OPT} -t '${SESSION}' && '${TMUX_BIN}' select-window -t '${SESSION}:${WIN_INDEX}' && '${TMUX_BIN}' select-pane -t '${TMUX_PANE}'"
    fi
fi

# --- Project name from cwd ---
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
PROJECT=""
if [ -n "$CWD" ]; then
    PROJECT=$(basename "$CWD")
fi

# --- Subtitle ---
SUBTITLE=""
if [ -n "$TMUX_INFO" ] && [ -n "$PROJECT" ]; then
    SUBTITLE="${TMUX_INFO} · ${PROJECT}"
elif [ -n "$TMUX_INFO" ]; then
    SUBTITLE="${TMUX_INFO}"
elif [ -n "$PROJECT" ]; then
    SUBTITLE="${PROJECT}"
fi

# --- Send notification ---
# Use custom ccnotifs.app if installed (for custom icon),
# otherwise fall back to terminal-notifier, then osascript.
CUSTOM_NOTIFIER="$HOME/.claude/ccnotifs.app/Contents/MacOS/terminal-notifier"

if [ -x "$CUSTOM_NOTIFIER" ]; then
    ARGS=(-title "$TITLE" -message "$BODY")
    [ -n "$SUBTITLE" ] && ARGS+=(-subtitle "$SUBTITLE")
    [ -n "$CLICK_CMD" ] && ARGS+=(-execute "$CLICK_CMD")
    "$CUSTOM_NOTIFIER" "${ARGS[@]}"
elif command -v terminal-notifier &>/dev/null; then
    ARGS=(-title "$TITLE" -message "$BODY" -sound "$SOUND")
    [ -n "$SUBTITLE" ] && ARGS+=(-subtitle "$SUBTITLE")
    [ -n "$CLICK_CMD" ] && ARGS+=(-execute "$CLICK_CMD")
    terminal-notifier "${ARGS[@]}"
else
    # Fallback: osascript (shows Script Editor icon)
    TITLE_ESC="${TITLE//\"/\\\"}"
    BODY_ESC="${BODY//\"/\\\"}"
    if [ -n "$SUBTITLE" ]; then
        SUBTITLE_ESC="${SUBTITLE//\"/\\\"}"
        osascript -e "display notification \"${BODY_ESC}\" with title \"${TITLE_ESC}\" subtitle \"${SUBTITLE_ESC}\" sound name \"${SOUND}\""
    else
        osascript -e "display notification \"${BODY_ESC}\" with title \"${TITLE_ESC}\" sound name \"${SOUND}\""
    fi
fi

# Play sound via afplay (routes through system audio, capturable by BlackHole etc.)
SOUND_FILE="/System/Library/Sounds/${SOUND}.aiff"
if [ -f "$SOUND_FILE" ]; then
    afplay "$SOUND_FILE" &
fi
