#!/usr/bin/env bash
#
# dotfiles-sync - keep two dotfiles repos in sync by content, never by history.
#
# Meant for a personal repo (github.com) and a work repo (GitHub Enterprise)
# that should stay identical apart from a few files. Changes travel between
# them as patch files over the tailnet (Taildrop), are reviewed before they are
# sent and again before they are applied, and each one lands in the receiving
# repo as a new commit made with that repo's own git identity. No commit, author
# or history ever crosses over, and neither repo gets a remote it could push to
# on the other side.
#
# Usage:
#   dotfiles-sync setup --label NAME --peer DEVICE [--email REGEX]
#   dotfiles-sync export [--no-send] [--yes]    send new commits to the peer
#   dotfiles-sync import [PATCH_OR_SNAPSHOT...] review and apply what arrived
#   dotfiles-sync snapshot [--no-send]          send every file (first sync)
#   dotfiles-sync baseline [COMMIT]             mark COMMIT (default HEAD) as synced
#   dotfiles-sync status
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
# The repo defaults to ~/dotfiles; set DOTFILES_SYNC_REPO or pass -C DIR.
# Under WSL it drives the Windows Tailscale client (tailscale.exe) and picks up
# files Taildrop saved to the Windows Downloads folder. On native Windows it runs
# in Git for Windows' bash; profile.ps1 wraps it as a `dotfiles-sync` command.

set -euo pipefail

PATCH_HEADER='# dotfiles-sync patch v1'
TRAILER='Dotfiles-Sync-Source'

REPO="${DOTFILES_SYNC_REPO:-${HOME}/dotfiles}"

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
  exit 1
}

##
# Prints a progress line.
# @param $* message
##
info() {
  printf '==> %s\n' "$*" >&2
}

##
# Runs git against the dotfiles repo.
# @param $@ git arguments
##
g() {
  git -C "$REPO" "$@"
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
  mkdir -p "$dir/outbox/sent" "$dir/inbox/done"
  printf '%s\n' "$dir"
}

##
# Asks a question on the terminal and prints the answer.
# @param $1 prompt
##
ask() {
  local answer=''
  printf '%s ' "$1" >"$TTY_OUT"
  IFS= read -r answer <"$TTY_IN" || true
  printf '%s\n' "$answer"
}

##
# Prints the .syncignore patterns, plus .syncignore itself, one per line.
##
syncignore_patterns() {
  printf '%s\n' '.syncignore'
  [ -f "$REPO/.syncignore" ] || return 0
  sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' "$REPO/.syncignore" | grep -v '^$' || true
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
  if command -v tailscale >/dev/null 2>&1; then
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
  printf '%s\n' "$HOME/Downloads"
  if is_wsl; then
    win_profile="$(cd / && cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"
    [ -n "$win_profile" ] && printf '%s/Downloads\n' "$(wslpath -u "$win_profile")"
  fi
}

##
# Fails when a file about to leave this machine contains a secret or a pattern
# from the local blocklist. Uses gitleaks too when it is installed.
# @param $1 file to scan (patch, or a directory of snapshot files)
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
  )
  local -a args=()
  local p
  for p in "${builtin[@]}"; do args+=(-e "$p"); done
  blocklist="$(state_dir)/blocklist"
  if [ -s "$blocklist" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] && [ "${p#\#}" = "$p" ] && args+=(-e "$p")
    done <"$blocklist"
  fi

  hits="$(grep -rnI -E "${args[@]}" "$target" 2>/dev/null | cut -c1-200 || true)"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" >&2
    die "outgoing changes match a secret or blocklist pattern - nothing was sent. Move the file to .syncignore or change it, then retry."
  fi

  if command -v gitleaks >/dev/null 2>&1; then
    if [ -d "$target" ]; then
      gitleaks dir --no-banner --redact "$target" >&2 \
        || die "gitleaks flagged the outgoing files - nothing was sent."
    else
      gitleaks stdin --no-banner --redact <"$target" >&2 \
        || die "gitleaks flagged the outgoing patch - nothing was sent."
    fi
  fi
}

##
# Sends a file to the peer with Taildrop, or leaves it in the outbox.
# @param $1 file
# @param $2 "send" or "keep"
# @return 0 when the file was sent or kept on request, 1 when sending failed
##
deliver() {
  local file="$1" mode="$2" peer ts
  if [ "$mode" = keep ]; then
    info "wrote $file - move it to the other machine and run 'dotfiles-sync import FILE' there"
    return 0
  fi
  peer="$(cfg peer)"
  [ -n "$peer" ] || die "no peer set: dotfiles-sync setup --peer DEVICE"
  ts="$(tailscale_bin)"
  [ -n "$ts" ] || die "tailscale CLI not found; rerun with --no-send"
  info "sending $(basename "$file") to $peer over Taildrop"
  if "$ts" file cp "$(ts_path "$ts" "$file")" "${peer}:"; then
    mv "$file" "$(dirname "$file")/sent/"
    return 0
  fi
  info "Taildrop failed; the file stays in $(dirname "$file")"
  return 1
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
# from the peer), has it reviewed and scanned, and sends it to the peer.
# @param $@ [--no-send] [--yes]
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
  state="$(state_dir)"
  base="$(cat "$state/last-export" 2>/dev/null || true)"
  [ -n "$base" ] || die "no baseline yet: dotfiles-sync baseline"
  g merge-base --is-ancestor "$base" HEAD || die "baseline $base is not in this branch's history"

  local -a pathspecs=()
  while IFS= read -r c; do pathspecs+=("$c"); done < <(exclude_pathspecs)

  out="$state/outbox/dotfiles-sync-${label}-$(date +%Y%m%dT%H%M%S).patch"
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
  scan_outgoing "$out"

  if [ "$yes" != yes ]; then
    answer="$(ask "Review the full patch in a pager first? [Y/n]")"
    case "$answer" in n|N) ;; *) ${PAGER:-less -R} "$out" <"$TTY_IN" >"$TTY_OUT" ;; esac
    answer="$(ask "Send these $n change(s)? [y/N]")"
    case "$answer" in y|Y) ;; *) rm -f "$out"; info "not sent"; return 0 ;; esac
  fi

  deliver "$out" "$mode" || return 1
  g rev-parse HEAD >"$state/last-export"
}

##
# Sends every non-ignored tracked file as a tarball, for the first sync when
# the two repos have drifted apart. The receiving side lays the files over its
# working tree for a normal review with git diff / git add -p.
# @param $@ [--no-send]
##
cmd_snapshot() {
  local mode=send label state tmp out answer
  [ "${1:-}" = "--no-send" ] && mode=keep
  label="$(cfg label)"
  [ -n "$label" ] || die "not set up: dotfiles-sync setup --label NAME --peer DEVICE"
  state="$(state_dir)"
  local -a pathspecs=()
  local p
  while IFS= read -r p; do pathspecs+=("$p"); done < <(exclude_pathspecs)

  tmp="$(mktemp -d)"
  g archive --format=tar HEAD -- . "${pathspecs[@]}" | tar -x -C "$tmp"
  scan_outgoing "$tmp"

  out="$state/outbox/dotfiles-sync-${label}-$(date +%Y%m%dT%H%M%S).snapshot.tar"
  tar -c -f "$out" -C "$tmp" .
  info "snapshot of $(find "$tmp" -type f | wc -l | tr -d ' ') files at $(g log -1 --format=%h HEAD)"
  rm -rf "$tmp"
  answer="$(ask "Send it? [y/N]")"
  case "$answer" in y|Y) ;; *) rm -f "$out"; info "not sent"; return 0 ;; esac
  deliver "$out" "$mode"
}

##
# Collects incoming files: Taildrop's inbox, the macOS app's ~/Downloads drop,
# and any paths given on the command line. Prints their paths, oldest first.
# @param $@ explicit files
##
collect_incoming() {
  local state inbox ts f
  state="$(state_dir)"
  inbox="$state/inbox"
  if [ $# -gt 0 ]; then
    for f in "$@"; do printf '%s\n' "$f"; done
    return 0
  fi
  ts="$(tailscale_bin)"
  [ -n "$ts" ] && "$ts" file get --conflict=rename "$(ts_path "$ts" "$inbox")" >/dev/null 2>&1 || true
  local dl
  while IFS= read -r dl; do
    for f in "$dl"/dotfiles-sync-*.patch "$dl"/dotfiles-sync-*.snapshot.tar; do
      [ -f "$f" ] && mv "$f" "$inbox/"
    done
  done < <(download_dirs)
  for f in "$inbox"/dotfiles-sync-*; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done | sort
}

##
# Lays a snapshot's files over the working tree for review.
# @param $1 snapshot tarball
##
import_snapshot() {
  local file="$1" tmp
  tmp="$(mktemp -d)"
  tar -x -f "$file" -C "$tmp"
  # this repo's own .syncignore still applies on the way in
  local p
  while IFS= read -r p; do
    (cd "$tmp" && rm -rf -- ${p%/}) 2>/dev/null || true
  done < <(syncignore_patterns)
  (cd "$tmp" && tar -c -f - .) | tar -x -f - -C "$REPO"
  rm -rf "$tmp"
  info "snapshot laid over the working tree. Review with 'git -C $REPO diff' and"
  info "'git -C $REPO add -p' (new files: git status), commit what you keep,"
  info "discard the rest, then run 'dotfiles-sync baseline' on BOTH machines."
}

##
# Walks the changes in one patch file, asking to apply or skip each one. Applied
# changes are committed with a trailer naming their source, which is how both
# re-imports and echoes back to the peer are recognised.
# @param $1 patch file
# @return 0 when every change was handled, 1 when stopped early
##
import_patch() {
  local file="$1" from dir state done_list skipped key sha subject body answer rc
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

  local -a apply_opts=()
  local o
  while IFS= read -r o; do apply_opts+=("$o"); done < <(exclude_apply_opts)

  done_list="$(g log --format="%(trailers:key=${TRAILER},valueonly)" HEAD)"
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

    while :; do
      printf '\n--- from %s: %s (%s)\n' "$from" "$subject" "${sha:0:10}" >"$TTY_OUT"
      git -C "$REPO" apply --stat "${apply_opts[@]}" "$body" >"$TTY_OUT" 2>&1 || true
      answer="$(ask "Apply? [y]es / [n]o, skip for good / [s]how diff / [q]uit")"
      case "$answer" in
        s|S) ${PAGER:-less -R} "$body" <"$TTY_IN" >"$TTY_OUT"; continue ;;
        n|N) printf '%s\n' "$key" >>"$skipped"; break ;;
        q|Q) rm -rf "$dir"; return 1 ;;
        y|Y)
          rc=0
          g apply --3way --index --whitespace=nowarn "${apply_opts[@]}" "$body" || rc=$?
          if [ "$rc" -ne 0 ]; then
            if g diff --quiet && g diff --cached --quiet; then
              info "this change does not apply here (the files differ too much); answer n to skip it"
              continue
            fi
            info "applied with conflicts. Resolve them, 'git add' the files, then run:"
            info "  git -C $REPO commit -m $(printf '%q' "sync(${from}): ${subject}") -m '${TRAILER}: ${key}'"
            info "and rerun 'dotfiles-sync import' for the rest."
            rm -rf "$dir"
            exit 1
          fi
          if g diff --cached --quiet; then
            info "nothing left to change (already present or ignored here)"
            printf '%s\n' "$key" >>"$skipped"
          else
            g commit -q -m "sync(${from}): ${subject}" -m "${TRAILER}: ${key}"
            info "committed $(g log -1 --format=%h)"
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
# Reviews and applies everything the peer sent.
# @param $@ explicit patch/snapshot files (default: Taildrop inbox)
##
cmd_import() {
  local f state n=0
  [ -n "$(cfg label)" ] || die "not set up: dotfiles-sync setup --label NAME --peer DEVICE"
  g diff --quiet && g diff --cached --quiet \
    || die "the repo has uncommitted changes to tracked files; commit or stash them first"
  state="$(state_dir)"

  while IFS= read -r f <&3; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    info "incoming: $(basename "$f")"
    case "$f" in
      *.snapshot.tar)
        import_snapshot "$f"
        mv "$f" "$state/inbox/done/" 2>/dev/null || true
        return 0
        ;;
      *)
        import_patch "$f" || return 0
        case "$f" in "$state/inbox/"*) mv "$f" "$state/inbox/done/" ;; esac
        ;;
    esac
  done 3< <(collect_incoming "$@")
  [ "$n" -gt 0 ] || info "nothing received"
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
    for c in $(g rev-list --first-parent "$base..HEAD"); do
      [ -z "$(g log -1 --format="%(trailers:key=${TRAILER},valueonly)" "$c")" ] && pending=$((pending + 1))
    done
    printf 'baseline:  %s\n' "$(g log -1 --format='%h %s' "$base")"
    printf 'to send:   %s commit(s)\n' "$pending"
  else
    printf 'baseline:  (none)\n'
  fi
  printf 'inbox:     %s file(s)\n' "$(find "$state/inbox" -maxdepth 1 -type f | wc -l | tr -d ' ')"
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
    setup) cmd_setup "$@" ;;
    export) cmd_export "$@" ;;
    import) cmd_import "$@" ;;
    snapshot) cmd_snapshot "$@" ;;
    baseline) cmd_baseline "$@" ;;
    status) cmd_status ;;
    check-push) cmd_check_push "$@" ;;
    -h|--help|help) sed -n '2,/^$/s/^# \{0,1\}//p' "$0" ;;
    *) die "unknown command: $cmd (try --help)" ;;
  esac
}

main "$@"
