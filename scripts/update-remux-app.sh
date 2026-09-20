#!/usr/bin/env bash
# Copyright (c) 2026, Ronen Druker. All rights reserved.
#
# Updates the Remux desktop app (https://github.com/lostb1t/remux) from GitHub releases. macOS
# builds only ship as a DMG, which neither Homebrew nor mise can manage (mise handles the headless
# `remux` CLI), so `ua` runs this script instead. If the app was running it is stopped with
# SIGTERM and relaunched, the same way switchbot's relogin watcher restarts it.
#
# Release channel: official releases. Pre-releases (Remux's rolling `nightly` build) are taken only
# when mise opts remux into them, so one flag drives both the CLI and the app:
#   ~/.config/mise/config.toml  "github:lostb1t/remux" = { ..., prerelease = true }
#   or mise's global setting     [settings] prereleases = true
# Neither is set, so both follow the tagged releases. Switching channels either way is that one
# flag: leaving the nightly channel installs the newest stable on the next run, without waiting for
# it to overtake the nightly - see is_release_newer below for why that needs saying.
#
# Environment:
#   REMUX_APP         app bundle to update (default: /Applications/Remux.app)
#   REMUX_URL         URL that must answer after a relaunch (default: http://127.0.0.1:3000/)
#   REMUX_PRERELEASE  1 or 0 to force or disable pre-releases, overriding mise

set -euo pipefail

readonly REPO="lostb1t/remux"
readonly TOOL="github:$REPO"
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

# Prints the CFBundleShortVersionString of an app bundle (e.g. 0.31.0 or
# 0.31.0-nightly.20260914.g31a31c22).
# $1: app bundle path
bundle_version() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist"
}

# Prints an app bundle's build time as YYYYMMDDHHMMSS (UTC), taken from a CFBundleVersion like
# 20260914.112937, or nothing when the bundle version has another format.
# $1: app bundle path
bundle_build_time() {
  local build
  build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist" 2>/dev/null)" || return 0
  if [[ "$build" =~ ^([0-9]{8})\.([0-9]{6})$ ]]; then
    echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  fi
}

# Succeeds when pre-releases should be installed: REMUX_PRERELEASE when set, otherwise mise's
# `prerelease` option on the remux tool or its global `prereleases` setting.
prerelease_enabled() {
  case "${REMUX_PRERELEASE:-}" in
    1 | true) return 0 ;;
    0 | false) return 1 ;;
  esac
  command -v mise >/dev/null 2>&1 || return 1

  # read the user's global configuration, not whatever project the caller happens to be in
  [[ "$(cd "$HOME" && mise settings get prereleases 2>/dev/null)" == true ]] && return 0
  [[ "$(cd "$HOME" && mise tool "$TOOL" --json 2>/dev/null | jq -r '.tool_options.prerelease // false')" == true ]]
}

# Prints the release to install as "tag<TAB>published_at<TAB>version<TAB>DMG URL": the most recently
# published non-draft release that has a DMG for this machine, skipping pre-releases unless enabled.
# The version comes from the DMG name when it carries one (nightly builds), otherwise from the tag.
# $1: true to include pre-releases, false otherwise
# $2: DMG architecture suffix (aarch64 or x86_64)
select_release() {
  local api="repos/$REPO/releases?per_page=30" json
  if ! { command -v gh >/dev/null 2>&1 && json="$(gh api "$api" 2>/dev/null)"; }; then
    json="$(curl -fsSL "https://api.github.com/$api")" || return 1
  fi

  jq -r --argjson pre "$1" --arg arch "$2" '
    ("-macos-" + $arch + "\\.dmg$") as $suffix
    | [ .[]
        | select((.draft | not) and ($pre or (.prerelease | not)))
        | . as $release
        | first(.assets[] | select(.name | test("^remux-desktop-(.+)?macos-" + $arch + "\\.dmg$")))
        | [ $release.tag_name,
            $release.published_at,
            ((.name | capture("^remux-desktop-(?<v>.+)" + $suffix).v) // ($release.tag_name | ltrimstr("v"))),
            .browser_download_url ]
      ]
    | sort_by(.[1])
    | (last // empty)
    | @tsv' <<<"$json"
}

# Succeeds when a release should replace the installed app. Builds are compared by time rather than
# by version number, because a nightly (0.31.0-nightly.20260914...) is newer than the stable 0.31.0
# it sorts below: the release's publish time must be later than the installed bundle's build time.
# Without a usable build time, falls back to comparing version numbers.
# $1: installed version
# $2: release version
# $3: release publish time (ISO 8601, UTC)
# $4: true when pre-releases are enabled, false on the stable channel
is_release_newer() {
  local built published="${3//[-:TZ]/}"

  # Coming off the nightly channel is a channel switch, not a downgrade, and the build-time
  # comparison below cannot express it: a nightly is built continuously, so it is almost always
  # newer than the newest tagged release and the machine would sit on it until some later stable
  # overtook it. 0.32.0-nightly.20260919 was built two and a half minutes after v0.33.0 was
  # published, which would have stranded it for a whole release. On stable, a nightly always loses.
  if [[ "$4" == false && "$1" == *-nightly.* ]]; then
    return 0
  fi

  built="$(bundle_build_time "$APP")"
  if [[ -n "$built" && "$published" =~ ^[0-9]{14}$ ]]; then
    ((10#$published > 10#$built))
  else
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$2" ]]
  fi
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

# Picks the newest release on the configured channel and installs it when it is newer.
main() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Remux.app updates are macOS only, skipping"
    return 0
  fi
  if [[ ! -d "$APP" ]]; then
    echo "$APP is not installed, skipping"
    return 0
  fi
  command -v jq >/dev/null 2>&1 || fail "jq is required to read Remux releases"

  local pre=false channel="stable"
  if prerelease_enabled; then
    pre=true
    channel="pre-release"
  fi

  local arch release tag published version url installed
  arch="$(dmg_arch)"
  release="$(select_release "$pre" "$arch")" || true
  [[ -n "$release" ]] || fail "could not determine the latest Remux $channel build"
  IFS=$'\t' read -r tag published version url <<<"$release"

  installed="$(bundle_version "$APP")"
  if [[ "$installed" == "$version" ]]; then
    echo "Remux $installed is up to date (channel: $channel)"
    return 0
  fi
  if ! is_release_newer "$installed" "$version" "$published" "$pre"; then
    echo "Remux $installed is newer than the latest $channel build ($version), keeping it"
    return 0
  fi
  echo "Updating Remux $installed -> $version (channel: $channel, release: $tag)"

  # explicit template: works with both BSD mktemp and the GNU coreutils one on PATH
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remux-update.XXXXXX")"
  trap cleanup EXIT

  local asset dmg new_app new_version
  asset="${url##*/}"
  dmg="$WORK_DIR/$asset"
  curl -fsSL --retry 3 -o "$dmg" "$url" || fail "could not download $asset"

  MOUNT_POINT="$WORK_DIR/mount"
  mkdir "$MOUNT_POINT"
  hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$MOUNT_POINT" "$dmg" ||
    fail "could not mount $asset"

  new_app="$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" -print -quit)"
  [[ -n "$new_app" ]] || fail "no app bundle found in $asset"
  new_version="$(bundle_version "$new_app")"
  [[ "$new_version" == "$version" ]] || fail "$asset contains Remux $new_version, expected $version"
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
