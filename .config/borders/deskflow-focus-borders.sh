#!/bin/bash
#
# Resident Deskflow-aware JankyBorders toggle (macOS side).
#
# The MacBook (Deskflow client) and the Dell (Deskflow server) each draw a
# border around their own focused window, so with both screens lit there is no
# single "this is where my keyboard goes" indicator. This script makes the Mac
# side follow Deskflow: the active-window border is shown only while Deskflow
# input is on this Mac, and made transparent while it is on the Dell (whose
# komorebi borders are toggled the same way by
# .config/komorebi/deskflow-focus-borders.ps1).
#
# Deskflow has no hooks, but the client logs `entering computer` /
# `leaving computer` (and `connected to server` / `disconnected from server`).
# This script tails that log; Deskflow must have file logging on (Deskflow
# GUI -> Settings -> "Log to file", path below). Calling `borders` while it is
# already running updates the running instance live.
#
# Started from AeroSpace's after-startup-command. Single-instance: a new run
# stops the previous one first, so running it again by hand is safe. It
# detaches itself (nohup, background) and returns at once, so closing the
# terminal it was started from does not stop it.
#
# Environment:
#   DESKFLOW_LOG  Deskflow client log file
#                 (default: ~/Library/Logs/Deskflow/deskflow.log)

# Re-launch detached from the terminal: a hang-up from closing it would
# otherwise stop the watcher and leave the border on for good.
if [[ -z "$DESKFLOW_FOCUS_BORDERS_DETACHED" ]]; then
  DESKFLOW_FOCUS_BORDERS_DETACHED=1 nohup "$0" "$@" >/dev/null 2>&1 &
  exit 0
fi

# Homebrew's bin may be missing when launched outside a login shell.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

LOG="${DESKFLOW_LOG:-$HOME/Library/Logs/Deskflow/deskflow.log}"
PIDFILE="${TMPDIR:-/tmp}/deskflow-focus-borders.pid"

# Active-border colour when this Mac has input (same as .aerospace.toml's
# borders line and bordersrc) and when it does not (fully transparent).
ON_COLOR=0xffebdbb2
OFF_COLOR=0x00000000

# Last state applied: "on", "off", or empty when not yet known.
state=""

# set_border STATE
#   Shows ("on") or hides ("off") the active-window border, skipping the
#   `borders` call when STATE is already in effect.
set_border() {
  [[ "$1" == "$state" ]] && return
  if [[ "$1" == on ]]; then
    borders active_color="$ON_COLOR"
  else
    borders active_color="$OFF_COLOR"
  fi
  state="$1"
}

# stop_previous
#   Terminates an earlier instance of this script recorded in PIDFILE, if it
#   is still running (its EXIT trap stops its tail as well).
stop_previous() {
  local old
  old=$(cat "$PIDFILE" 2>/dev/null) || return
  if [[ -n "$old" && "$old" != "$$" ]] &&
    ps -p "$old" -o command= 2>/dev/null | grep -q deskflow-focus-borders; then
    kill "$old" 2>/dev/null
  fi
}

# cleanup
#   Stops the tail, restores the border and removes the pidfile (if still
#   ours) when this instance exits.
cleanup() {
  [[ -n "$tail_pid" ]] && kill "$tail_pid" 2>/dev/null
  set_border on
  [[ "$(cat "$PIDFILE" 2>/dev/null)" == "$$" ]] && rm -f "$PIDFILE"
}

stop_previous
echo $$ >"$PIDFILE"
trap cleanup EXIT
# No HUP: nohup ignores it, so the watcher outlives its terminal.
trap 'exit 0' TERM INT

# Input is local until Deskflow says otherwise (e.g. Mac used on its own).
set_border on

# tail -F follows the file by name, so it waits for the log to appear and
# survives Deskflow rotating it. -n 0: only react to switches from now on.
exec 3< <(tail -F -n 0 "$LOG" 2>/dev/null)
tail_pid=$!

# connected
#   Succeeds when the Deskflow client process holds an established TCP
#   connection (to the server), i.e. the Dell can still own the input.
connected() {
  lsof -nP -a -c deskflow-core -iTCP -sTCP:ESTABLISHED >/dev/null 2>&1
}

# Seconds between connection checks while the border is hidden.
WATCHDOG_INTERVAL=5

while true; do
  if read -r -t "$WATCHDOG_INTERVAL" line <&3; then
    case "$line" in
      # Only a clean disconnect logs "disconnected from server"; a server that
      # vanishes (Dell asleep, network drop, keep-alive timeout) logs
      # "server is dead" and then "failed to connect to server: ..." retries.
      *"disconnected from server"* | *"entering computer"* | \
        *"server is dead"* | *"failed to connect to server"*)
        set_border on ;;
      # A client can never hold the cursor at the moment it connects, so input
      # is on the Dell then.
      *"leaving computer"* | *"connected to server"*)
        set_border off ;;
    esac
  elif kill -0 "$tail_pid" 2>/dev/null; then
    # Timed out with no log line (macOS /bin/bash 3.2 returns 1 on a read
    # timeout, same as EOF, so a live tail is what tells them apart).
    # Watchdog for drops that leave nothing in the log (Mac slept, Deskflow
    # quit, log rotated mid-event): if the border is hidden but there is no
    # live connection, input must be local.
    [[ "$state" == off ]] && ! connected && set_border on
  else
    break # tail ended
  fi
done
