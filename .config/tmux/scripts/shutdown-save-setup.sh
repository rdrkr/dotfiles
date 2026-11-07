#!/usr/bin/env bash
#
# shutdown-save-setup.sh - installs the service that saves tmux as the machine
# goes down, once per machine.
#
# tmux-restore's own install.sh does this too, but it also rewrites tmux.conf,
# which here is managed by hand and shared between machines. Run this by hand on
# each machine that should have it: it adds a login item, so tmux.conf does not
# start it. Safe to re-run; it returns straight away once set up.
#
#   macOS  a LaunchAgent running tmux-restore's watcher, built from source
#   Linux  a systemd user service, where a user session exists
#
# Anything missing just means no save at shutdown; the periodic save still runs.
# The label and unit name are upstream's, so its --uninstall removes these too.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="${SCRIPT_DIR}/../plugins/tmux-restore"
LABEL="io.github.andrewboldi.tmux-restore"
UNIT="tmux-restore.service"

##
# Tells whether a command is on PATH.
#
# @param $1 Command name.
# @return 0 when it is available.
##
have() { command -v "$1" >/dev/null 2>&1; }

##
# Builds the shutdown watcher and loads it as a LaunchAgent.
#
# launchd's environment has neither Homebrew on PATH nor a UTF-8 locale; in the C
# locale tmux turns the tabs in resurrect's output into "_", which leaves the save
# empty. Both are therefore set in the plist.
#
# @return 0 when set up or skipped, non-zero when the watcher failed to build.
##
setup_launch_agent() {
  local bin="${PLUGIN}/bin/tmux-restore-shutdown"
  local plist="${HOME}/Library/LaunchAgents/${LABEL}.plist"

  [ -x "$bin" ] && [ -f "$plist" ] && return 0
  have swiftc || return 0

  mkdir -p "$(dirname "$bin")" "$(dirname "$plist")"
  swiftc -O -o "$bin" "${PLUGIN}/scripts/shutdown-watcher.swift" 2>/dev/null || return 1

  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>${bin}</string><string>${PLUGIN}/scripts/save-now.sh</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>LANG</key><string>en_US.UTF-8</string>
  </dict>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/tmux-restore.log</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/tmux-restore.log</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PLIST

  # not fatal outside a GUI login (over SSH): launchd loads the plist at next login
  launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
}

##
# Installs and starts the systemd user service, pointed at the plugin's real
# location. Skipped without a user session (WSL by default) or without gdbus,
# which shutdown-save.sh needs to hear about the shutdown.
##
setup_systemd_unit() {
  local dir="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"

  [ -f "${dir}/${UNIT}" ] && return 0
  have systemctl && have gdbus || return 0
  systemctl --user show-environment >/dev/null 2>&1 || return 0

  mkdir -p "$dir"
  sed "s|^ExecStart=.*|ExecStart=\"$(cd "$PLUGIN" && pwd)/scripts/shutdown-save.sh\"|" \
    "${PLUGIN}/systemd/${UNIT}" >"${dir}/${UNIT}"
  systemctl --user daemon-reload
  systemctl --user enable -q --now "$UNIT"
}

[ -d "$PLUGIN" ] || exit 0

case "$(uname -s)" in
  Darwin) setup_launch_agent ;;
  Linux) setup_systemd_unit ;;
esac
