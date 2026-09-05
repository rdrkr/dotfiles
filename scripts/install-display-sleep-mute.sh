#!/bin/bash
#
# install-display-sleep-mute.sh
#
# Builds display-sleep-mute.swift, links its LaunchAgent into
# ~/Library/LaunchAgents, and (re)loads the agent. Idempotent - safe to re-run
# after editing the Swift source to pick up the new build. Needs no root.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.ronendruker.display-sleep-mute"
SOURCE="${SCRIPT_DIR}/display-sleep-mute.swift"
PLIST="${SCRIPT_DIR}/${LABEL}.plist"
BINARY="${HOME}/.local/bin/display-sleep-mute"
INSTALLED_PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

echo "==> Building ${BINARY}"
mkdir -p "$(dirname "${BINARY}")"
# Build beside the target and move into place, so a failed build never leaves a
# half-written binary that launchd would then try to restart in a loop.
swiftc -O "${SOURCE}" -o "${BINARY}.new"
mv -f "${BINARY}.new" "${BINARY}"

echo "==> Linking ${INSTALLED_PLIST}"
mkdir -p "$(dirname "${INSTALLED_PLIST}")"
ln -sfn "${PLIST}" "${INSTALLED_PLIST}"

echo "==> Loading ${LABEL}"
# bootout fails when the job is not loaded; that is the normal first-run case.
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${INSTALLED_PLIST}"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

echo "==> Done. Log: ${HOME}/Library/Logs/display-sleep-mute.log"
