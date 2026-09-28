#!/usr/bin/env bash
#
# persist-forget.sh - drop tmux-persist's saved snapshots of a session that was
# closed on purpose, so the next boot-time restore does not bring it back.
#
# Usage: persist-forget.sh <session-name> <tmux-socket-path>
#
# Run from the `session-closed` hook in tmux.conf. That hook also fires for
# sessions torn down by `kill-server` (for some of them - tmux races its own
# exit), and those should survive like a crash or reboot does. So this waits a
# moment and only forgets the session while the server is still up: a server
# that is going away kills this job or fails the liveness check first. The
# server outliving its last session relies on `exit-empty off`.

session="$1"
socket="$2"
[ -n "$session" ] && [ -n "$socket" ] || exit 0

# point every plain `tmux` call (ours and persist's helpers) at this server
export TMUX="${socket},0,0"

sleep 1

# server gone (kill-server, crash): keep the session's snapshots
tmux show-options -sv exit-empty >/dev/null 2>&1 || exit 0
# a session of that name exists again (e.g. recreated by a restore): keep them
tmux has-session -t "=${session}" 2>/dev/null && exit 0

save_script="$(tmux show-options -gqv @persist-save-script-path)"
[ -n "$save_script" ] || exit 0

# reuse tmux-persist's own path helpers (persist_dir, filename sanitizing)
# shellcheck source=/dev/null
source "$(dirname "$save_script")/helpers.sh" || exit 0

dir="$(persist_dir)"
name="$(_sanitize_session_for_path "$session")"

# the `last` pointer is what `restore.sh all` enumerates; the timestamped
# snapshots and their companions go too, since tmux-persist only prunes
# snapshots of sessions that still have a pointer
rm -f "${dir}/${name}_last" "${dir}/${name}_last.hash" \
  "${dir}/${name}_"????????T??????.* "${dir}/${name}_"????????T??????_pane_contents.tgz
