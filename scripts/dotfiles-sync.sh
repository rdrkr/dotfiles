#!/usr/bin/env bash
#
# dotfiles-sync - keep two dotfiles repos in sync by content, never by history.
#
# Meant for a personal repo (github.com) and a work repo (GitHub Enterprise)
# that should stay identical apart from a few files. Changes travel between
# them as patch files over the tailnet (Taildrop), and each one lands in the
# receiving repo as a new commit made with that repo's own git identity. No
# commit, author or history ever crosses over, and neither repo gets a remote it
# could push to on the other side.
#
# Usage:
#   dotfiles-sync setup --label NAME --peer DEVICE [--email REGEX]
#   dotfiles-sync export [--no-send] [--yes]    send new commits to the peer
#   dotfiles-sync import [--auto] [FILE...]     review and apply what arrived
#   dotfiles-sync snapshot [--no-send] [--yes]  send every file (first sync)
#   dotfiles-sync baseline [COMMIT]             mark COMMIT (default HEAD) as synced
#   dotfiles-sync flush                         send patches still queued in the outbox
#   dotfiles-sync auto                          one unattended sync cycle
#   dotfiles-sync schedule | unschedule         run 'auto' continuously (launchd / cron)
#   dotfiles-sync with-lock CMD [ARG...]        run CMD while holding the sync lock
#   dotfiles-sync status
#
# Continuous sync: 'schedule' installs a launchd agent on macOS (every 2 minutes
# and whenever something lands in ~/Downloads) or a cron entry on Linux, each
# running 'auto': commit local changes, apply what the peer sent, send what is
# new. Outgoing changes are still scanned for secrets and never sent when the
# scan fails. An incoming change that does not apply cleanly is moved to
# .git/dotfiles-sync/inbox/held/, a notification is shown, and nothing more is
# applied until an interactive 'dotfiles-sync import' has dealt with it.
# Snapshots are never applied unattended. On macOS the launchd job can only see
# ~/Downloads (where Taildrop saves files) once /bin/bash has Full Disk Access
# (System Settings > Privacy & Security).
#
# Per-clone settings live in the repo's local git config (never committed):
#   dotfiles-sync.label   this side's name, e.g. "personal" or "work"
#   dotfiles-sync.peer    Tailscale device name of the other machine
#   dotfiles-sync.email   regex every pushed author/committer email must match
#
# Files that must never cross are listed in .syncignore (one gitignore-style
# pattern per line; each repo has its own). Extra patterns that must never leave
# this machine - corporate hostnames, internal URLs - go in
# .git/dotfiles-sync/blocklist (extended regexes, one per line); keep that file
# out of the repo, since the patterns themselves are what must not leak.
#
# Snapshots only add and overwrite files: a file deleted on the other side stays
# here until you delete it yourself.
#
# The repo defaults to ~/dotfiles; set DOTFILES_SYNC_REPO or pass -C DIR.
# DOTFILES_SYNC_TAILSCALE overrides the tailscale CLI, DOTFILES_SYNC_DOWNLOADS
# (":"-separated) the folders searched for Taildrop files, and
# DOTFILES_SYNC_NO_NOTIFY=1 turns desktop notifications off (tests use these).
# Under WSL it drives the Windows Tailscale client (tailscale.exe) and picks up
# files Taildrop saved to the Windows Downloads folder. Native Windows uses
# scripts/dotfiles-sync.ps1, which speaks the same patch format; this script
# still runs in Git for Windows' bash as a fallback.

set -euo pipefail

PATCH_HEADER='# dotfiles-sync patch v1'
TRAILER='Dotfiles-Sync-Source'
AUTO_COMMIT_MSG='chore(sync): auto-commit local changes'
LAUNCHD_LABEL='com.dotfiles.sync'

REPO="${DOTFILES_SYNC_REPO:-${HOME}/dotfiles}"

# set while this process holds the sync lock / runs an 'auto' cycle
LOCK_DIR=''
AUTO_RUN=no
LAST_RUN_STATUS=''
LAST_RUN_MSG=''

# Where prompts are read from and written to: the controlling terminal when
# there is one; otherwise (e.g. Git Bash started from PowerShell, where
# /dev/tty may not open) the script's own stdin and stderr.
if (exec </dev/tty) 2>/dev/null; then
  TTY_IN=/dev/tty
  TTY_OUT=/dev/tty
else
  TTY_IN=/dev/stdin
  TTY_OUT=/dev/stderr
fi

##
# Prints an error and exits.
# @param $* message
##
die() {
  printf 'dotfiles-sync: %s\n' "$*" >&2
  log "error: $*"
  exit 1
}

##
# Prints a progress line and records it in the sync log.
# @param $* message
##
info() {
  printf '==> %s\n' "$*" >&2
  log "$*"
}

##
# Appends a timestamped line to .git/dotfiles-sync/sync.log, keeping the log
# under about 1 MB. Does nothing before the repo is known.
# @param $* message
##
log() {
  local file
  [ -n "${SYNC_LOG:-}" ] || return 0
  file="$SYNC_LOG"
  printf '%s [%s] %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$$" "$*" >>"$file" 2>/dev/null || return 0
  if [ "$(wc -c <"$file" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    tail -n 2000 "$file" >"$file.tmp" 2>/dev/null && mv "$file.tmp" "$file"
  fi
  return 0
}

##
# Shows a desktop notification (scripts/notify.sh, else osascript/notify-send)
# and logs it. Never fails.
# @param $1 title
# @param $2 message
##
notify() {
  local title="$1" msg="$2" helper="$REPO/scripts/notify.sh"
  log "notify: $title - $msg"
  [ "${DOTFILES_SYNC_NO_NOTIFY:-}" = 1 ] && return 0
  if [ -x "$helper" ]; then
    "$helper" --title "$title" --message "$msg" --timeout 30 --skip-tmux-check >/dev/null 2>&1 &
  elif command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${msg//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$msg" >/dev/null 2>&1 || true
  fi
  return 0
}

##
# Runs git against the dotfiles repo.
# @param $@ git arguments
##
g() {
  git -C "$REPO" "$@"
}

##
# Commits what is staged, retrying a few times: a commit can fail for a moment
# while another program (an editor's git integration, a backup) holds the index
# lock or touches the working tree during the pre-commit hook. git's error
# output is logged.
# @param $@ git commit arguments (e.g. -m MESSAGE -m TRAILER)
# @return 0 when committed, 1 when every attempt failed
##
commit_with_retry() {
  local attempt out
  for attempt in 1 2 3; do
    if out="$(g commit -q "$@" 2>&1)"; then
      [ -z "$out" ] || printf '%s\n' "$out" >&2
      return 0
    fi
    printf '%s\n' "$out" >&2
    log "git commit failed (attempt $attempt): $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-400)"
    sleep $((3 * attempt))
  done
  return 1
}

##
# Prints a dotfiles-sync.* setting from the repo's local git config.
# @param $1 setting name without the "dotfiles-sync." prefix
##
cfg() {
  g config --get "dotfiles-sync.$1" || true
}

##
# Prints (and creates) the per-clone state directory inside .git.
##
state_dir() {
  local dir
  dir="$(posix_path "$(g rev-parse --absolute-git-dir)")/dotfiles-sync"
  mkdir -p "$dir/outbox/sent" "$dir/outbox/manual" "$dir/inbox/done" "$dir/inbox/held"
  printf '%s\n' "$dir"
}

##
# Succeeds unless scripts/dotfiles-sync.ps1 (or install.ps1) on Windows holds
# its lock - an exclusive handle on the "lock" file, which WSL and Git Bash
# cannot open while it is held. The file only exists in a clone that Windows
# also uses, so elsewhere this always succeeds.
# @param $1 state directory
##
windows_lock_free() {
  [ -f "$1/lock" ] || return 0
  (exec 3<>"$1/lock") 2>/dev/null
}

##
# Takes the per-clone sync lock (a directory, so it works without flock),
# honouring the Windows implementation's lock too when the clone is shared with
# WSL. A lock left by a process that no longer runs is taken over. Re-entrant
# within one run.
# @param $1 seconds to wait for it (default 0)
# @return 0 when held, 1 when another run still has it
##
acquire_lock() {
  local state dir waited=0 pid
  [ -n "$LOCK_DIR" ] && return 0
  state="$(state_dir)"
  dir="$state/lock.d"
  while :; do
    if mkdir "$dir" 2>/dev/null; then
      windows_lock_free "$state" && break
      rm -rf "$dir"
    else
      pid="$(cat "$dir/pid" 2>/dev/null || true)"
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        rm -rf "$dir"
        continue
      fi
      # a lock without a pid more than a minute old was left mid-creation
      if [ -z "$pid" ] && [ -n "$(find "$dir" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
        rm -rf "$dir"
        continue
      fi
    fi
    [ "$waited" -lt "${1:-0}" ] || return 1
    sleep 1
    waited=$((waited + 1))
  done
  printf '%s\n' "$$" >"$dir/pid"
  LOCK_DIR="$dir"
  return 0
}

##
# Releases the sync lock if this process holds it.
##
release_lock() {
  if [ -n "$LOCK_DIR" ]; then
    rm -rf "$LOCK_DIR"
    LOCK_DIR=''
  fi
}

##
# EXIT trap: records how an 'auto' cycle ended and releases the lock.
##
on_exit() {
  local rc=$?
  if [ "$AUTO_RUN" = yes ]; then
    [ "$rc" -eq 0 ] || LAST_RUN_STATUS=error
    printf '%s %s %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "${LAST_RUN_STATUS:-ok}" "$LAST_RUN_MSG" \
      >"$(state_dir)/last-run" 2>/dev/null || true
  fi
  release_lock
}
trap on_exit EXIT

##
# Takes the lock for an interactive command, or stops when a sync is running.
##
require_lock() {
  acquire_lock 0 || die "another dotfiles-sync run holds the lock ($(state_dir)/lock.d); try again shortly"
}

##
# Asks a question on the terminal and prints the answer. Fails when there is
# nothing to read (no terminal, input closed), so callers never loop on an
# empty answer; call it as: answer="$(ask "...")" || exit 1
# @param $1 prompt
##
ask() {
  local answer=''
  printf '%s ' "$1" >"$TTY_OUT"
  if ! IFS= read -r answer <"$TTY_IN" && [ -z "$answer" ]; then
    printf '\ndotfiles-sync: no answer (input closed) - run this in a terminal\n' >&2
    return 1
  fi
  printf '%s\n' "$answer"
}

##
# Prints the non-empty, non-comment lines of a pattern file, without the CRLF
# line endings and UTF-8 BOM that files written from Windows can carry.
# @param $1 file (missing is fine)
##
pattern_lines() {
  local line
  [ -f "$1" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#$'\xef\xbb\xbf'}"
    line="${line%%#*}"
    line="${line%"${line##*[![:space:]]}"}"
    line="${line#"${line%%[![:space:]]*}"}"
    [ -n "$line" ] && printf '%s\n' "$line"
  done <"$1"
  return 0
}

##
# Prints the .syncignore patterns, plus .syncignore itself, one per line. A
# leading "/" is dropped (patterns are matched from the repo root anyway, and
# git refuses "/x" as a path outside the repo); "!" negations are not supported
# and are left out.
##
syncignore_patterns() {
  local p
  printf '%s\n' '.syncignore'
  pattern_lines "$REPO/.syncignore" | while IFS= read -r p; do
    case "$p" in '!'*) continue ;; esac
    p="${p#/}"
    [ -n "$p" ] && printf '%s\n' "$p"
  done
  return 0
}

##
# Prints `git diff` pathspecs excluding every .syncignore pattern, one per line.
# A trailing "/" means the whole directory.
##
exclude_pathspecs() {
  local p
  syncignore_patterns | while IFS= read -r p; do
    case "$p" in
      */) printf ':(exclude,glob)%s**\n' "$p" ;;
      *)  printf ':(exclude,glob)%s\n' "$p" ;;
    esac
  done
}

##
# Prints `git apply --exclude` options for every .syncignore pattern.
##
exclude_apply_opts() {
  local p
  syncignore_patterns | while IFS= read -r p; do
    case "$p" in
      */) printf -- '--exclude=%s*\n' "$p" ;;
      *)  printf -- '--exclude=%s\n' "$p" ;;
    esac
  done
}

##
# Succeeds when running under Git Bash / MSYS on Windows.
##
is_msys() {
  case "${OSTYPE:-}" in msys* | cygwin*) return 0 ;; esac
  return 1
}

##
# Prints a path in the POSIX form this script works with; Git for Windows
# reports paths as "C:/...", which tar and globbing do not treat as local.
# @param $1 path
##
posix_path() {
  if is_msys && command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  else
    printf '%s\n' "$1"
  fi
}

##
# Succeeds when running inside WSL.
##
is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null
}

##
# Prints the path of the tailscale CLI, or nothing when it is not installed.
# The macOS app ships its CLI inside the app bundle; under WSL the device is
# usually the Windows host, reached through the Windows client's tailscale.exe.
##
tailscale_bin() {
  if [ -n "${DOTFILES_SYNC_TAILSCALE:-}" ]; then
    printf '%s\n' "$DOTFILES_SYNC_TAILSCALE"
  elif command -v tailscale >/dev/null 2>&1; then
    command -v tailscale
  elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then
    printf '%s\n' /Applications/Tailscale.app/Contents/MacOS/Tailscale
  elif is_wsl && command -v tailscale.exe >/dev/null 2>&1; then
    command -v tailscale.exe
  elif is_wsl && [ -x "/mnt/c/Program Files/Tailscale/tailscale.exe" ]; then
    printf '%s\n' "/mnt/c/Program Files/Tailscale/tailscale.exe"
  elif is_msys && [ -x "/c/Program Files/Tailscale/tailscale.exe" ]; then
    printf '%s\n' "/c/Program Files/Tailscale/tailscale.exe"
  fi
}

##
# Prints a path in the form the tailscale CLI expects: a Windows path for the
# Windows client (from WSL or Git Bash), unchanged otherwise.
# @param $1 tailscale CLI path
# @param $2 path to convert
##
ts_path() {
  if is_wsl && [ "${1%.exe}" != "$1" ]; then
    wslpath -w "$2"
  elif is_msys && command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$2"
  else
    printf '%s\n' "$2"
  fi
}

##
# Prints the folders Taildrop may have saved incoming files to on its own: the
# macOS and Windows clients drop them into the user's Downloads folder (under
# WSL, the Windows one).
##
download_dirs() {
  local win_profile
  if [ -n "${DOTFILES_SYNC_DOWNLOADS+set}" ]; then
    [ -n "$DOTFILES_SYNC_DOWNLOADS" ] && printf '%s\n' "$DOTFILES_SYNC_DOWNLOADS" | tr ':' '\n'
    return 0
  fi
  printf '%s\n' "$HOME/Downloads"
  if is_wsl; then
    win_profile="$(cd / && cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"
    [ -n "$win_profile" ] && printf '%s/Downloads\n' "$(wslpath -u "$win_profile")"
  fi
}

##
# Checks a file about to leave this machine for secrets and patterns from the
# local blocklist, and runs gitleaks too when it is installed. Hits are printed
# with the secrets themselves masked.
# @param $1 file to scan (patch, or a directory of snapshot files)
# @return 0 when clean, 1 when something matched
##
scan_outgoing() {
  local target="$1" blocklist hits
  local -a builtin=(
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'gh[pousr]_[A-Za-z0-9]{36,}'
    'github_pat_[A-Za-z0-9_]{22,}'
    'AKIA[0-9A-Z]{16}'
    'xox[abprs]-[A-Za-z0-9-]{10,}'
    'glpat-[A-Za-z0-9_-]{20,}'
    'sk-(ant-)?[A-Za-z0-9_-]{20,}'
    # any browser cookie-jar line (Netscape format), whatever the cookie holds
    $'(TRUE|FALSE)\t/[^\t]*\t(TRUE|FALSE)\t[0-9]+\t[^\t]+\t[^\t]+'
  )
  local -a args=() redact=()
  local p
  for p in "${builtin[@]}"; do
    args+=(-e "$p")
    redact+=(-e "s#${p}#[redacted]#g")
  done
  blocklist="$(state_dir)/blocklist"
  while IFS= read -r p; do
    args+=(-e "$p")
  done < <(pattern_lines "$blocklist")

  # report file:line with the secrets themselves masked, so a failed scan never
  # puts them on screen (blocklist hits are shown, they are this machine's own)
  if [ -d "$target" ]; then
    hits="$(cd "$target" && grep -rnI -E "${args[@]}" . 2>/dev/null || true)"
  else
    hits="$(grep -nI -E "${args[@]}" "$target" 2>/dev/null || true)"
  fi
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed -E "${redact[@]}" | cut -c1-160 >&2
    info "outgoing changes match a secret or blocklist pattern (above) - nothing was sent. Untrack or fix those files, or list them in .syncignore, then retry."
    return 1
  fi

  if command -v gitleaks >/dev/null 2>&1; then
    if [ -d "$target" ]; then
      gitleaks dir --no-banner --redact "$target" >&2 \
        || { info "gitleaks flagged the outgoing files - nothing was sent."; return 1; }
    else
      gitleaks stdin --no-banner --redact <"$target" >&2 \
        || { info "gitleaks flagged the outgoing patch - nothing was sent."; return 1; }
    fi
  fi
  return 0
}

##
# Sends every file queued in the outbox to the peer with Taildrop, oldest first,
# moving each to outbox/sent/ once it has gone. Stops at the first failure so
# the peer always receives patches in order.
# @return 0 when the outbox is empty afterwards, 1 when something is still queued
##
flush_outbox() {
  local state peer ts f
  local -a queued=()
  state="$(state_dir)"
  for f in "$state"/outbox/dotfiles-sync-*; do
    [ -f "$f" ] && queued+=("$f")
  done
  [ "${#queued[@]}" -gt 0 ] || return 0
  peer="$(cfg peer)"
  [ -n "$peer" ] || { info "no peer set (dotfiles-sync setup --peer DEVICE); ${#queued[@]} file(s) stay queued"; return 1; }
  ts="$(tailscale_bin)"
  [ -n "$ts" ] || { info "tailscale CLI not found; ${#queued[@]} file(s) stay queued in $state/outbox"; return 1; }
  while IFS= read -r f; do
    info "sending $(basename "$f") to $peer over Taildrop"
    if "$ts" file cp "$(ts_path "$ts" "$f")" "${peer}:" </dev/null; then
      mv "$f" "$state/outbox/sent/"
    else
      info "Taildrop failed; $(basename "$f") stays queued and is retried on the next run"
      return 1
    fi
  done < <(printf '%s\n' "${queued[@]}" | sort)
  return 0
}

##
# Puts a finished patch or snapshot in the outbox and sends the queue, or leaves
# it in outbox/manual/ for a manual transfer.
# @param $1 file
# @param $2 "send" or "keep"
# @return 0 when queued (sent or not) or kept, 1 when the send failed
##
deliver() {
  local file="$1" mode="$2" state
  state="$(state_dir)"
  if [ "$mode" = keep ]; then
    mv "$file" "$state/outbox/manual/"
    info "wrote $state/outbox/manual/$(basename "$file") - move it to the other machine and run 'dotfiles-sync import FILE' there"
    return 0
  fi
  mv "$file" "$state/outbox/"
  flush_outbox
}

##
# Prints the commit exports start after: last-export, or - when a rebase has
# rewritten that commit out of this branch - its merge base with HEAD.
##
export_base() {
  local base state fallback
  state="$(state_dir)"
  base="$(cat "$state/last-export" 2>/dev/null || true)"
  [ -n "$base" ] || die "no baseline yet: dotfiles-sync baseline"
  if ! g merge-base --is-ancestor "$base" HEAD 2>/dev/null; then
    fallback="$(g merge-base "$base" HEAD 2>/dev/null)" \
      || die "baseline $base is unknown here; run 'dotfiles-sync baseline' once both repos match"
    info "baseline ${base:0:10} is no longer on this branch (rewritten by a rebase?); continuing from ${fallback:0:10}"
    base="$fallback"
  fi
  printf '%s\n' "$base"
}

##
# Stores this repo's sync settings and installs the pre-push identity check.
# @param $@ --label NAME --peer DEVICE [--email REGEX]
##
cmd_setup() {
  local hook
  while [ $# -gt 0 ]; do
    case "$1" in
      --label) g config dotfiles-sync.label "$2"; shift 2 ;;
      --peer)  g config dotfiles-sync.peer "$2"; shift 2 ;;
      --email) g config dotfiles-sync.email "$2"; shift 2 ;;
      *) die "setup: unknown option $1" ;;
    esac
  done
  [ -n "$(cfg label)" ] || die "setup needs --label (e.g. personal or work)"

  hook="$(g rev-parse --absolute-git-dir)/hooks/pre-push"
  if [ -e "$hook" ] && ! grep -q 'dotfiles-sync' "$hook"; then
    info "a pre-push hook already exists at $hook; add this line to it yourself:"
    info "  \"$REPO/scripts/dotfiles-sync.sh\" -C \"$REPO\" check-push \"\$@\" || exit 1"
  else
    mkdir -p "$(dirname "$hook")"
    cat >"$hook" <<EOF
#!/bin/sh
# installed by dotfiles-sync setup: refuses to push commits made under another identity
exec "$REPO/scripts/dotfiles-sync.sh" -C "$REPO" check-push "\$@"
EOF
    chmod +x "$hook"
  fi

  if [ ! -s "$(state_dir)/last-export" ]; then
    g rev-parse HEAD >"$(state_dir)/last-export"
    info "baseline set to HEAD - run this once both repos match (see 'snapshot')"
  fi
  cmd_status
}

##
# pre-push hook body: refuses the push when a new commit's author or committer
# email does not match dotfiles-sync.email.
# @param $1 remote name (from git)
# stdin: "<local ref> <local sha> <remote ref> <remote sha>" lines (from git)
##
cmd_check_push() {
  local remote="${1:-}" pattern local_sha remote_sha zero bad=''
  pattern="$(cfg email)"
  [ -n "$pattern" ] || exit 0
  zero='0000000000000000000000000000000000000000'
  while read -r _ local_sha _ remote_sha; do
    [ "$local_sha" = "$zero" ] && continue
    local range
    if [ "$remote_sha" = "$zero" ]; then
      range="$(g rev-list "$local_sha" --not --remotes="$remote")"
    else
      range="$(g rev-list "$remote_sha..$local_sha")"
    fi
    local c
    for c in $range; do
      g log -1 --format='%ae%n%ce' "$c" | grep -qvE "$pattern" \
        && bad="${bad}$(g log -1 --format='  %h %ae / %ce  %s' "$c")"$'\n'
    done
  done
  if [ -n "$bad" ]; then
    printf 'dotfiles-sync: push refused - these commits use an identity not matching %s:\n%s' "$pattern" "$bad" >&2
    exit 1
  fi
}

##
# Marks a commit as the last one the peer has, so the next export starts after it.
# @param $1 commit (default HEAD)
##
cmd_baseline() {
  local commit
  commit="$(g rev-parse --verify "${1:-HEAD}^{commit}")" || die "no such commit: ${1:-HEAD}"
  printf '%s\n' "$commit" >"$(state_dir)/last-export"
  info "baseline: $(g log -1 --format='%h %s' "$commit")"
}

##
# Builds a patch of every commit since the last export (skipping ones that came
# from the peer), has it reviewed (unless --yes) and scanned, queues it in the
# outbox and sends the queue to the peer.
# @param $@ [--no-send] [--yes]
# @return 0 when queued or nothing to send, 1 when the scan blocked it or the send failed
##
cmd_export() {
  local mode=send yes=no label base state out chunk c n=0 answer
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-send) mode=keep; shift ;;
      --yes) yes=yes; shift ;;
      *) die "export: unknown option $1" ;;
    esac
  done
  label="$(cfg label)"
  [ -n "$label" ] || die "not set up: dotfiles-sync setup --label NAME --peer DEVICE"
  require_lock
  state="$(state_dir)"
  base="$(export_base)"

  local -a pathspecs=()
  while IFS= read -r c; do pathspecs+=("$c"); done < <(exclude_pathspecs)

  out="$state/dotfiles-sync-${label}-$(date +%Y%m%dT%H%M%S).patch"
  chunk="$(mktemp)"
  printf '%s\n# from: %s\n# created: %s\n' "$PATCH_HEADER" "$label" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$out"

  for c in $(g rev-list --reverse --first-parent "$base..HEAD"); do
    # commits that were themselves imported from the peer go no further
    if [ -n "$(g log -1 --format="%(trailers:key=${TRAILER},valueonly)" "$c")" ]; then
      continue
    fi
    g diff --binary --full-index "${c}^1" "$c" -- . "${pathspecs[@]}" >"$chunk"
    [ -s "$chunk" ] || continue
    {
      printf '=== change %s ===\n' "$c"
      printf 'Subject: %s\n' "$(g log -1 --format=%s "$c")"
      cat "$chunk"
    } >>"$out"
    n=$((n + 1))
  done
  rm -f "$chunk"

  if [ "$n" -eq 0 ]; then
    rm -f "$out"
    g rev-parse HEAD >"$state/last-export"
    info "nothing to send"
    return 0
  fi

  info "$n change(s) since $(g log -1 --format='%h' "$base"):"
  grep -E '^(=== change|Subject:)' "$out" | sed -n 's/^Subject: /  - /p' >&2
  if ! scan_outgoing "$out"; then
    rm -f "$out"
    return 1
  fi

  if [ "$yes" != yes ]; then
    answer="$(ask "Review the full patch in a pager first? [Y/n]")" || exit 1
    case "$answer" in n|N) ;; *) ${PAGER:-less -R} "$out" <"$TTY_IN" >"$TTY_OUT" ;; esac
    answer="$(ask "Send these $n change(s)? [y/N]")" || exit 1
    case "$answer" in y|Y) ;; *) rm -f "$out"; info "not sent"; return 0 ;; esac
  fi

  # once queued, the patch is the peer's copy of these commits: later runs
  # start after them and a failed send is retried from the outbox
  g rev-parse HEAD >"$state/last-export"
  deliver "$out" "$mode"
}

##
# Sends every non-ignored tracked file as a tarball, for the first sync when
# the two repos have drifted apart. The receiving side lays the files over its
# working tree for a normal review with git diff / git add -p.
# @param $@ [--no-send] [--yes]
##
cmd_snapshot() {
  local mode=send yes=no label state tmp out answer
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-send) mode=keep; shift ;;
      --yes) yes=yes; shift ;;
      *) die "snapshot: unknown option $1" ;;
    esac
  done
  label="$(cfg label)"
  [ -n "$label" ] || die "not set up: dotfiles-sync setup --label NAME --peer DEVICE"
  require_lock
  state="$(state_dir)"
  local -a pathspecs=()
  local p
  while IFS= read -r p; do pathspecs+=("$p"); done < <(exclude_pathspecs)

  tmp="$(mktemp -d)"
  g archive --format=tar HEAD -- . "${pathspecs[@]}" | tar -x -C "$tmp"
  if ! scan_outgoing "$tmp"; then
    rm -rf "$tmp"
    exit 1
  fi

  out="$state/dotfiles-sync-${label}-$(date +%Y%m%dT%H%M%S).snapshot.tar"
  tar -c -f "$out" -C "$tmp" .
  info "snapshot of $(find "$tmp" -type f | wc -l | tr -d ' ') files at $(g log -1 --format=%h HEAD)"
  rm -rf "$tmp"
  if [ "$yes" != yes ]; then
    answer="$(ask "Send it? [y/N]")" || exit 1
    case "$answer" in y|Y) ;; *) rm -f "$out"; info "not sent"; return 0 ;; esac
  fi
  deliver "$out" "$mode"
}

##
# Sends whatever is still queued in the outbox.
##
cmd_flush() {
  require_lock
  flush_outbox
}

##
# Moves files Taildrop delivered (its inbox, the ~/Downloads drop) into
# .git/dotfiles-sync/inbox/. Warns when a Downloads folder exists but cannot be
# read, which on macOS means the launchd job lacks Full Disk Access.
##
receive_incoming() {
  local state inbox ts f dl
  state="$(state_dir)"
  inbox="$state/inbox"
  ts="$(tailscale_bin)"
  [ -n "$ts" ] && "$ts" file get --conflict=rename "$(ts_path "$ts" "$inbox")" </dev/null >/dev/null 2>&1 || true
  while IFS= read -r dl; do
    [ -d "$dl" ] || continue
    if ! ls "$dl" >/dev/null 2>&1; then
      info "cannot read $dl - on macOS give /bin/bash Full Disk Access (System Settings > Privacy & Security)"
      LAST_RUN_MSG="${LAST_RUN_MSG:+$LAST_RUN_MSG; }cannot read $dl"
      continue
    fi
    for f in "$dl"/dotfiles-sync-*.patch "$dl"/dotfiles-sync-*.snapshot.tar; do
      [ -f "$f" ] && mv "$f" "$inbox/"
    done
  done < <(download_dirs)
  return 0
}

##
# Prints "inbox" or "held" when a file sits directly in this clone's inbox or
# inbox/held folder (however its path is spelled), nothing otherwise.
# @param $1 file
##
inbox_place() {
  local dir state
  dir="$(cd "$(dirname "$(posix_path "$1")")" 2>/dev/null && pwd -P)" || return 0
  state="$(cd "$(state_dir)" && pwd -P)"
  if [ "$dir" = "$state/inbox" ]; then
    printf 'inbox\n'
  elif [ "$dir" = "$state/inbox/held" ]; then
    printf 'held\n'
  fi
  return 0
}

##
# Prints the incoming files to work through, oldest first: held ones before new
# ones, or the paths given on the command line.
# @param $1 "all" to include held files, "new" for the inbox only
# @param $@ (after $1) explicit files
##
collect_incoming() {
  local which="$1" state f
  shift
  if [ $# -gt 0 ]; then
    for f in "$@"; do printf '%s\n' "$f"; done
    return 0
  fi
  state="$(state_dir)"
  receive_incoming
  if [ "$which" = all ]; then
    for f in "$state"/inbox/held/dotfiles-sync-*; do
      [ -f "$f" ] && printf '%s\n' "$f"
    done | sort
  fi
  for f in "$state"/inbox/dotfiles-sync-*; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done | sort
  return 0
}

##
# Lays a snapshot's files over the working tree for review. This repo's own
# .syncignore still applies: matching paths are dropped from the unpacked copy
# first (anchored "/x" patterns are taken relative to the snapshot root, "!"
# patterns are ignored, and nothing outside the temporary copy is touched).
# @param $1 snapshot tarball
##
import_snapshot() {
  local file tmp p m
  file="$(posix_path "$1")"
  tmp="$(mktemp -d)"
  tar -x -f "$file" -C "$tmp"
  while IFS= read -r p; do
    case "$p" in '!'*) continue ;; esac
    p="${p#/}"
    p="${p%/}"
    [ -n "$p" ] || continue
    (
      cd "$tmp" || exit 0
      # unquoted on purpose: the pattern is globbed inside the temporary copy
      for m in $p; do
        case "$m" in /* | .. | ../* | */../* | */..) continue ;; esac
        [ -e "$m" ] || [ -L "$m" ] || continue
        rm -rf -- "./$m"
      done
    )
  done < <(syncignore_patterns)
  (cd "$tmp" && tar -c -f - .) | tar -x -f - -C "$REPO"
  rm -rf "$tmp"
  info "snapshot laid over the working tree. Review with 'git -C $REPO diff' and"
  info "'git -C $REPO add -p' (new files: git status), commit what you keep,"
  info "discard the rest, then run 'dotfiles-sync baseline' on BOTH machines."
}

##
# Prints `git apply --exclude` options for the paths a change touches that this
# repo deliberately does not track: ignored by .gitignore (or info/exclude) and
# not in the index. The peer may still track such files - e.g. from before they
# were ignored - and applying them here would fail or start tracking them.
# @param $1 the change's diff file
# @param $2 file listing every path in this repo's index
##
ignored_path_excludes() {
  awk '/^diff --git a\// { a = $3; b = $4; sub(/^a\//, "", a); sub(/^b\//, "", b); print a; print b }' "$1" \
    | sort -u | grep -vxF -f "$2" | g check-ignore --stdin 2>/dev/null | sed 's/^/--exclude=/'
  return 0
}

##
# Walks the changes in one patch file. Interactively it asks to apply or skip
# each one; with --auto it applies them all and stops at the first that does
# not apply cleanly. Applied changes are committed with a trailer naming their
# source, which is how both re-imports and echoes back to the peer are recognised.
# @param $1 patch file
# @param $2 "auto" or "ask"
# @return 0 when every change was handled, 1 when stopped early (quit, or not a
#   patch), 2 when --auto hit a change that needs a human
##
import_patch() {
  local file="$1" how="$2" from dir state done_list skipped key sha subject body answer rc tracked
  state="$(state_dir)"
  [ "$(head -n 1 "$file")" = "$PATCH_HEADER" ] || { info "not a dotfiles-sync patch: $file"; return 1; }
  from="$(sed -n 's/^# from: //p' "$file" | head -n 1)"
  [ "$from" != "$(cfg label)" ] || { info "skipping $file: it came from this side"; return 0; }

  dir="$(mktemp -d)"
  # split into dir/NNNN files: line 1 "sha", line 2 "Subject: ...", then the diff
  awk -v dir="$dir" '
    /^=== change [0-9a-f]+ ===$/ { n++; f = sprintf("%s/%04d", dir, n); print $3 > f; next }
    n { print >> f }
  ' "$file"

  local -a apply_opts=() opts=()
  local o
  while IFS= read -r o; do apply_opts+=("$o"); done < <(exclude_apply_opts)

  done_list="$(g log --format="%(trailers:key=${TRAILER},valueonly)" HEAD)"
  # a dot-file, so the "$dir"/* loop below never takes it for a change
  tracked="$dir/.tracked"
  g ls-files >"$tracked"
  skipped="$state/skipped"
  touch "$skipped"

  local chunk
  for chunk in "$dir"/*; do
    [ -f "$chunk" ] || continue
    sha="$(sed -n 1p "$chunk")"
    subject="$(sed -n '2s/^Subject: //p' "$chunk")"
    key="$from $sha"
    if printf '%s\n' "$done_list" | grep -qxF "$key" || grep -qxF "$key" "$skipped"; then
      continue
    fi
    body="${chunk}.diff"
    tail -n +3 "$chunk" >"$body"
    opts=("${apply_opts[@]}")
    while IFS= read -r o; do opts+=("$o"); done < <(ignored_path_excludes "$body" "$tracked")

    if [ "$how" = auto ]; then
      rc=0
      g apply --3way --index --whitespace=nowarn "${opts[@]}" "$body" >&2 || rc=$?
      if [ "$rc" -ne 0 ]; then
        # the cycle started from a clean, committed tree: drop the partial apply
        g reset -q --hard HEAD
        info "change from $from does not apply cleanly: $subject (${sha:0:10})"
        rm -rf "$dir"
        return 2
      fi
      if g diff --cached --quiet; then
        info "already present or ignored here: $subject"
        printf '%s\n' "$key" >>"$skipped"
      elif commit_with_retry -m "sync(${from}): ${subject}" -m "${TRAILER}: ${key}"; then
        info "applied from $from: $subject ($(g log -1 --format=%h))"
      else
        # never leave it staged: the next cycle would commit it as a local
        # change, without the trailer, and send it back
        g reset -q --hard HEAD
        rm -rf "$dir"
        die "could not commit the change from $from ($subject); the patch stays in the inbox and is retried on the next run"
      fi
      continue
    fi

    while :; do
      printf '\n--- from %s: %s (%s)\n' "$from" "$subject" "${sha:0:10}" >"$TTY_OUT"
      git -C "$REPO" apply --stat "${opts[@]}" "$body" >"$TTY_OUT" 2>&1 || true
      answer="$(ask "Apply? [y]es / [n]o, skip for good / [s]how diff / [q]uit")" || exit 1
      case "$answer" in
        s|S) ${PAGER:-less -R} "$body" <"$TTY_IN" >"$TTY_OUT"; continue ;;
        n|N) printf '%s\n' "$key" >>"$skipped"; break ;;
        q|Q) rm -rf "$dir"; return 1 ;;
        y|Y)
          rc=0
          g apply --3way --index --whitespace=nowarn "${opts[@]}" "$body" || rc=$?
          if [ "$rc" -ne 0 ]; then
            if g diff --quiet && g diff --cached --quiet; then
              info "this change does not apply here (the files differ too much); answer n to skip it"
              continue
            fi
            # tells 'auto' not to commit the half-resolved tree without the trailer
            printf '%s\n' "$key" >"$state/resolving"
            info "applied with conflicts. Resolve them, 'git add' the files, then run:"
            info "  git -C $REPO commit -m $(printf '%q' "sync(${from}): ${subject}") -m '${TRAILER}: ${key}'"
            info "and rerun 'dotfiles-sync import' for the rest."
            rm -rf "$dir"
            exit 1
          fi
          if g diff --cached --quiet; then
            info "nothing left to change (already present or ignored here)"
            printf '%s\n' "$key" >>"$skipped"
          elif commit_with_retry -m "sync(${from}): ${subject}" -m "${TRAILER}: ${key}"; then
            info "committed $(g log -1 --format=%h)"
          else
            printf '%s\n' "$key" >"$state/resolving"
            info "the commit failed (reason above). Fix it, then commit the staged change yourself:"
            info "  git -C $REPO commit -m $(printf '%q' "sync(${from}): ${subject}") -m '${TRAILER}: ${key}'"
            rm -rf "$dir"
            exit 1
          fi
          break
          ;;
      esac
    done
  done
  rm -rf "$dir"
  return 0
}

##
# Applies what the peer sent. Interactively it also works through files held by
# an earlier unattended run; with --auto it pauses while anything is held,
# applies patches without asking, and holds (with a notification) snapshots and
# patches that do not apply cleanly.
# @param $@ [--auto] [explicit patch/snapshot files] (default: Taildrop inbox)
##
cmd_import() {
  local f state n=0 how=ask rc base held where
  if [ "${1:-}" = "--auto" ]; then
    how=auto
    shift
  fi
  [ -n "$(cfg label)" ] || die "not set up: dotfiles-sync setup --label NAME --peer DEVICE"
  require_lock
  g diff --quiet && g diff --cached --quiet \
    || die "the repo has uncommitted changes to tracked files; commit or stash them first"
  state="$(state_dir)"

  if [ "$how" = auto ] && [ $# -eq 0 ]; then
    held="$(find "$state/inbox/held" -maxdepth 1 -type f -name 'dotfiles-sync-*' | wc -l | tr -d ' ')"
    if [ "$held" -gt 0 ]; then
      receive_incoming
      info "$held held file(s) wait for an interactive 'dotfiles-sync import'; not applying anything new"
      LAST_RUN_STATUS=held
      return 0
    fi
  fi

  while IFS= read -r f <&3; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    base="$(basename "$f")"
    info "incoming: $base"
    case "$f" in
      *.snapshot.tar)
        if [ "$how" = auto ]; then
          mv "$f" "$state/inbox/held/" 2>/dev/null || true
          notify "dotfiles-sync" "A snapshot arrived ($base). Run 'dotfiles-sync import' to review it."
          LAST_RUN_STATUS=held
          LAST_RUN_MSG="snapshot $base held"
          return 0
        fi
        import_snapshot "$f"
        mv "$f" "$state/inbox/done/" 2>/dev/null || true
        return 0
        ;;
      *)
        rc=0
        import_patch "$f" "$how" || rc=$?
        where="$(inbox_place "$f")"
        case "$rc" in
          0) [ -n "$where" ] && mv "$f" "$state/inbox/done/" ;;
          2)
            [ "$where" = inbox ] && mv "$f" "$state/inbox/held/"
            notify "dotfiles-sync" "A change in $base conflicts with this repo. Run 'dotfiles-sync import' to resolve it."
            LAST_RUN_STATUS=held
            LAST_RUN_MSG="conflict in $base"
            return 0
            ;;
          *) return 0 ;;
        esac
        ;;
    esac
  done 3< <(if [ "$how" = auto ]; then collect_incoming new "$@"; else collect_incoming all "$@"; fi)
  [ "$n" -gt 0 ] || info "nothing received"
}

##
# One unattended cycle: commit local changes, apply what the peer sent, send
# what is new, retry anything still queued. Skips quietly while another run
# holds the lock, a merge/rebase is in progress, or an interactive import is
# waiting for its conflicts to be committed.
##
cmd_auto() {
  local state gitdir rc blocked_head head
  [ -n "$(cfg label)" ] || die "not set up: dotfiles-sync setup --label NAME --peer DEVICE"
  if ! acquire_lock 0; then
    info "another dotfiles-sync run holds the lock; skipping this cycle"
    return 0
  fi
  AUTO_RUN=yes
  state="$(state_dir)"
  gitdir="$(posix_path "$(g rev-parse --absolute-git-dir)")"

  if [ -e "$gitdir/MERGE_HEAD" ] || [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ] \
    || [ -e "$gitdir/CHERRY_PICK_HEAD" ] || [ -n "$(g ls-files -u)" ]; then
    LAST_RUN_STATUS=skipped
    LAST_RUN_MSG="merge, rebase or conflict in progress"
    info "a merge, rebase or conflict is in progress; skipping this cycle"
    return 0
  fi
  if [ -e "$state/resolving" ]; then
    if [ -n "$(g status --porcelain)" ]; then
      LAST_RUN_STATUS=skipped
      LAST_RUN_MSG="waiting for the conflicted import to be committed"
      info "an interactive import is being resolved; skipping this cycle"
      return 0
    fi
    rm -f "$state/resolving"
  fi

  # 1. local changes become a commit made with this repo's own identity
  if [ -n "$(g status --porcelain)" ]; then
    g add -A
    # staged local changes are safe to leave: the next cycle commits them
    commit_with_retry -m "$AUTO_COMMIT_MSG" || die "could not commit local changes; retrying on the next run"
    info "committed local changes ($(g log -1 --format=%h))"
  fi

  # 2. apply what arrived
  cmd_import --auto

  # 3. send what is new, and whatever an earlier run could not send
  rc=0
  cmd_export --yes || rc=$?
  head="$(g rev-parse HEAD)"
  if [ "$rc" -ne 0 ] && [ "$(cat "$state/last-export" 2>/dev/null)" != "$head" ]; then
    # export only fails before queueing when the secret scan blocked it
    LAST_RUN_STATUS=blocked
    LAST_RUN_MSG="outgoing changes failed the secret scan"
    blocked_head="$(cat "$state/scan-blocked" 2>/dev/null || true)"
    if [ "$blocked_head" != "$head" ]; then
      printf '%s\n' "$head" >"$state/scan-blocked"
      notify "dotfiles-sync" "Outgoing changes match a secret or blocklist pattern and were not sent. See $state/sync.log."
    fi
    flush_outbox || true
  elif [ "$rc" -ne 0 ]; then
    rm -f "$state/scan-blocked"
    LAST_RUN_STATUS="${LAST_RUN_STATUS:-queued}"
    LAST_RUN_MSG="${LAST_RUN_MSG:-$(count_sync_files "$state/outbox") file(s) waiting for the peer}"
  else
    rm -f "$state/scan-blocked"
  fi

  # 4. retry what earlier runs could not send (export only sends when it queued something)
  if [ "$(count_sync_files "$state/outbox")" -gt 0 ] && ! flush_outbox; then
    [ -n "$LAST_RUN_STATUS" ] || LAST_RUN_STATUS=queued
    [ -n "$LAST_RUN_MSG" ] || LAST_RUN_MSG="$(count_sync_files "$state/outbox") file(s) waiting for the peer"
  fi
  return 0
}

##
# Installs the continuous sync job: a launchd agent on macOS (every 2 minutes,
# and whenever something lands in ~/Downloads), a cron entry elsewhere.
##
cmd_schedule() {
  local self plist log_file cron_line path_env
  self="$REPO/scripts/dotfiles-sync.sh"
  [ -n "$(cfg label)" ] || die "not set up: dotfiles-sync setup --label NAME --peer DEVICE"
  case "$(uname -s)" in
    Darwin)
      plist="$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist"
      log_file="$(state_dir)/launchd.log"
      path_env="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      mkdir -p "$(dirname "$plist")"
      cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LAUNCHD_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(xml_escape "$self")</string>
    <string>-C</string>
    <string>$(xml_escape "$REPO")</string>
    <string>auto</string>
  </array>
  <key>StartInterval</key><integer>120</integer>
  <key>WatchPaths</key>
  <array><string>$(xml_escape "$HOME/Downloads")</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>${path_env}</string></dict>
  <key>StandardOutPath</key><string>$(xml_escape "$log_file")</string>
  <key>StandardErrorPath</key><string>$(xml_escape "$log_file")</string>
</dict>
</plist>
EOF
      launchctl bootout "gui/$(id -u)/${LAUNCHD_LABEL}" >/dev/null 2>&1 || true
      launchctl bootstrap "gui/$(id -u)" "$plist" || die "launchctl bootstrap failed for $plist"
      info "launchd agent ${LAUNCHD_LABEL} installed ($plist)"
      info "give /bin/bash Full Disk Access (System Settings > Privacy & Security) so it can read ~/Downloads"
      ;;
    *)
      cron_line="*/2 * * * * \"$self\" -C \"$REPO\" auto >/dev/null 2>&1 # dotfiles-sync"
      { crontab -l 2>/dev/null | grep -v '# dotfiles-sync$' || true; printf '%s\n' "$cron_line"; } | crontab -
      info "cron entry installed: $cron_line"
      ;;
  esac
}

##
# Removes the continuous sync job installed by 'schedule'.
##
cmd_unschedule() {
  local plist
  case "$(uname -s)" in
    Darwin)
      plist="$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist"
      launchctl bootout "gui/$(id -u)/${LAUNCHD_LABEL}" >/dev/null 2>&1 || true
      rm -f "$plist"
      info "launchd agent ${LAUNCHD_LABEL} removed"
      ;;
    *)
      { crontab -l 2>/dev/null | grep -v '# dotfiles-sync$' || true; } | crontab -
      info "cron entry removed"
      ;;
  esac
}

##
# Escapes a string for an XML text node.
# @param $1 text
##
xml_escape() {
  local s="$1"
  # "\&": bash 5.2+ would otherwise put the matched text where "&" stands
  s="${s//&/\&amp;}"
  s="${s//</\&lt;}"
  s="${s//>/\&gt;}"
  printf '%s' "$s"
}

##
# Runs a command while holding the sync lock (waiting up to 5 minutes for it),
# so backups and other git jobs never interleave with a sync cycle.
# @param $@ command and arguments
##
cmd_with_lock() {
  [ $# -gt 0 ] || die "with-lock needs a command"
  acquire_lock 300 || die "timed out waiting for the sync lock"
  "$@"
}

##
# Counts the files in a directory whose names start with dotfiles-sync-.
# @param $1 directory
##
count_sync_files() {
  find "$1" -maxdepth 1 -type f -name 'dotfiles-sync-*' 2>/dev/null | wc -l | tr -d ' '
}

##
# Shows this side's sync settings and what is waiting in each direction.
##
cmd_status() {
  local state base pending=0 c
  state="$(state_dir)"
  base="$(cat "$state/last-export" 2>/dev/null || true)"
  printf 'repo:      %s\n' "$REPO"
  printf 'label:     %s\n' "$(cfg label)"
  printf 'peer:      %s\n' "$(cfg peer)"
  printf 'email:     %s\n' "$(cfg email)"
  if [ -n "$base" ]; then
    local -a pathspecs=()
    while IFS= read -r c; do pathspecs+=("$c"); done < <(exclude_pathspecs)
    base="$(export_base 2>/dev/null || printf '%s\n' "$base")"
    for c in $(g rev-list --first-parent "$base..HEAD"); do
      [ -z "$(g log -1 --format="%(trailers:key=${TRAILER},valueonly)" "$c")" ] || continue
      g diff --quiet "${c}^1" "$c" -- . "${pathspecs[@]}" || pending=$((pending + 1))
    done
    printf 'baseline:  %s\n' "$(g log -1 --format='%h %s' "$base" 2>/dev/null || printf '%s (missing)' "$base")"
    printf 'to send:   %s commit(s)\n' "$pending"
  else
    printf 'baseline:  (none)\n'
  fi
  printf 'queued:    %s file(s) in outbox\n' "$(count_sync_files "$state/outbox")"
  printf 'inbox:     %s file(s)\n' "$(count_sync_files "$state/inbox")"
  printf 'held:      %s file(s)%s\n' "$(count_sync_files "$state/inbox/held")" \
    "$([ "$(count_sync_files "$state/inbox/held")" -gt 0 ] && printf ' - run dotfiles-sync import')"
  printf 'last run:  %s\n' "$(cat "$state/last-run" 2>/dev/null || printf '(never)')"
}

main() {
  if [ "${1:-}" = "-C" ]; then
    REPO="$2"
    shift 2
  fi
  [ -d "$REPO" ] || die "repo not found: $REPO (set DOTFILES_SYNC_REPO or pass -C DIR)"
  REPO="$(cd "$REPO" && git rev-parse --show-toplevel)" || die "not a git repo: $REPO"
  REPO="$(posix_path "$REPO")"

  local cmd="${1:-status}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    check-push | -h | --help | help) ;;
    *) SYNC_LOG="$(state_dir)/sync.log" ;;
  esac
  case "$cmd" in
    setup) cmd_setup "$@" ;;
    export) cmd_export "$@" ;;
    import) cmd_import "$@" ;;
    snapshot) cmd_snapshot "$@" ;;
    baseline) cmd_baseline "$@" ;;
    flush) cmd_flush ;;
    auto) cmd_auto ;;
    schedule) cmd_schedule ;;
    unschedule) cmd_unschedule ;;
    with-lock) cmd_with_lock "$@" ;;
    status) cmd_status ;;
    check-push) cmd_check_push "$@" ;;
    -h|--help|help) sed -n '2,/^$/s/^# \{0,1\}//p' "$0" ;;
    *) die "unknown command: $cmd (try --help)" ;;
  esac
}

main "$@"
