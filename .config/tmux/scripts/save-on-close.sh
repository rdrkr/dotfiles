#!/usr/bin/env bash
#
# save-on-close.sh - save right away when a session is closed on purpose, so the
# next boot-time restore does not bring it back.
#
# Usage: save-on-close.sh <session-name> <tmux-socket-path>
#
# Run from the `session-closed` hook in tmux.conf. tmux-continuum's periodic save
# only runs while a client is attached, so closing the last session would
# otherwise leave it in the snapshot for good.
#
# That hook also fires for sessions torn down by `kill-server` (for some of them -
# tmux races its own exit), and those should survive like a crash or reboot does.
# So this waits a moment and only saves while the server is still up: a server
# that is going away kills this job or fails the liveness check first. The server
# outliving its last session relies on `exit-empty off`.

session="$1"
socket="$2"
[ -n "$session" ] && [ -n "$socket" ] || exit 0

# internal sessions, e.g. the throwaway one a boot-time restore closes while the
# restored agents are still starting up: a save then would miss them
case "$session" in __*) exit 0 ;; esac

# point every plain `tmux` call (ours and resurrect's) at this server
export TMUX="${socket},0,0"

sleep 1

# server gone (kill-server, crash): keep the snapshot as it is
tmux show-options -sv exit-empty >/dev/null 2>&1 || exit 0

save_script="$(tmux show-options -gqv @resurrect-save-script-path)"
[ -x "$save_script" ] && exec "$save_script" quiet
exit 0
