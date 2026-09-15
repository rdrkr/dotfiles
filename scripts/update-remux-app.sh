#!/usr/bin/env bash
# Copyright (c) 2026, Ronen Druker. All rights reserved.
#
# Updates the Remux desktop app (https://github.com/lostb1t/remux) to the latest stable GitHub
# release. macOS builds only ship as a DMG, which neither Homebrew nor mise can manage (mise
# handles the headless `remux` CLI), so `ua` runs this script instead. If the app was running it
# is stopped with SIGTERM and relaunched, the same way switchbot's relogin watcher restarts it.
#
# Environment:
#   REMUX_APP  app bundle to update (default: /Applications/Remux.app)
#   REMUX_URL  URL that must answer after a relaunch (default: http://127.0.0.1:3000/)

set -euo pipefail

readonly REPO="lostb1t/remux"
readonly APP="${REMUX_APP:-/Applications/Remux.app}"
readonly URL="${REMUX_URL:-http://127.0.0.1:3000/}"
readonly QUIT_TIMEOUT=10
readonly LAUNCH_TIMEOUT=60

# Scratch directory holding the DMG, its mount point and the previous app bundle
WORK_DIR=""
# Mount point of the attached DMG, empty while nothing is attached
MOUNT_POINT=""
# Whether the app was running before the update and must be running again afterwards
WAS_RUNNING=false

# Prints an error and exits; the EXIT trap then cleans up and relaunches the app if needed.
# $*: message
fail() {
  echo "error: $*" >&2
  exit 1
}

# Detaches the DMG, removes the scratch directory and relaunches the app if the update stopped it.
cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach -quiet -force "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [[ -n "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
  if [[ "$WAS_RUNNING" == true ]] && ! app_running && [[ -d "$APP" ]]; then
    open -a "$APP" || true
  fi
}

# Prints the CFBundleShortVersionString of an app bundle.
# $1: app bundle path
bundle_version() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist"
}

# Prints the tag of the latest stable release. /releases/latest never returns pre-releases, so
# nightly builds are not picked up.
latest_tag() {
  local api="repos/$REPO/releases/latest"
  if command -v gh >/dev/null 2>&1 && gh api "$api" --jq .tag_name 2>/dev/null; then
    return 0
  fi
  curl -fsSL "https://api.github.com/$api" | sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p'
}

# Succeeds when the second version is strictly newer than the first.
# $1: installed version
# $2: candidate version
is_newer() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$2" ]]
}

# Prints the architecture suffix used by the release DMGs for this machine.
dmg_arch() {
  case "$(uname -m)" in
    arm64) echo aarch64 ;;
    x86_64) echo x86_64 ;;
    *) fail "unsupported architecture: $(uname -m)" ;;
  esac
}

# Succeeds when the app's executable is running.
app_running() {
  pgrep -f "$APP/Contents/MacOS/" >/dev/null 2>&1
}

# Stops the app with SIGTERM, so the media server can close its database, and waits for it to exit.
stop_app() {
  pkill -TERM -f "$APP/Contents/MacOS/" || true
  for ((i = 0; i < QUIT_TIMEOUT; i++)); do
    app_running || return 0
    sleep 1
  done
  fail "Remux did not quit within ${QUIT_TIMEOUT}s"
}

# Waits for the relaunched server to answer HTTP requests.
wait_for_server() {
  local deadline=$((SECONDS + LAUNCH_TIMEOUT))
  while ((SECONDS < deadline)); do
    if curl -s -o /dev/null --max-time 2 "$URL"; then
      return 0
    fi
    sleep 2
  done
  fail "Remux relaunched but $URL is not answering after ${LAUNCH_TIMEOUT}s"
}

# Replaces the installed app with the given bundle, restoring the previous one on failure.
# $1: new app bundle
replace_app() {
  local staged="$APP.new" previous="$WORK_DIR/previous.app"

  rm -rf "$staged"
  ditto "$1" "$staged" || fail "could not copy the new app to $staged"
  mv "$APP" "$previous" || fail "could not move the installed app aside"
  if ! mv "$staged" "$APP"; then
    mv "$previous" "$APP"
    fail "could not install the new app, restored the previous version"
  fi
}

# Checks for a newer release and installs it.
main() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Remux.app updates are macOS only, skipping"
    return 0
  fi
  if [[ ! -d "$APP" ]]; then
    echo "$APP is not installed, skipping"
    return 0
  fi

  local installed tag latest
  installed="$(bundle_version "$APP")"
  tag="$(latest_tag)" || true
  [[ -n "$tag" ]] || fail "could not determine the latest Remux release"
  latest="${tag#v}"

  if ! is_newer "$installed" "$latest"; then
    echo "Remux $installed is up to date (latest release: $latest)"
    return 0
  fi
  echo "Updating Remux $installed -> $latest"

  # explicit template: works with both BSD mktemp and the GNU coreutils one on PATH
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remux-update.XXXXXX")"
  trap cleanup EXIT

  local asset dmg new_app new_version
  asset="remux-desktop-macos-$(dmg_arch).dmg"
  dmg="$WORK_DIR/$asset"
  curl -fsSL --retry 3 -o "$dmg" "https://github.com/$REPO/releases/download/$tag/$asset" ||
    fail "could not download $asset"

  MOUNT_POINT="$WORK_DIR/mount"
  mkdir "$MOUNT_POINT"
  hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$MOUNT_POINT" "$dmg" ||
    fail "could not mount $asset"

  new_app="$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" -print -quit)"
  [[ -n "$new_app" ]] || fail "no app bundle found in $asset"
  new_version="$(bundle_version "$new_app")"
  [[ "$new_version" == "$latest" ]] || fail "$asset contains Remux $new_version, expected $latest"
  codesign --verify --deep --strict "$new_app" || fail "code signature check failed for $asset"

  if app_running; then
    WAS_RUNNING=true
    echo "Stopping Remux"
    stop_app
  fi

  replace_app "$new_app"
  echo "Installed Remux $(bundle_version "$APP")"

  if [[ "$WAS_RUNNING" == true ]]; then
    echo "Relaunching Remux"
    open -a "$APP"
    wait_for_server
    echo "Remux is answering on $URL"
  fi
}

main "$@"
