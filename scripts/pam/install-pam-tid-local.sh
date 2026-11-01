#!/usr/bin/env bash
# Copyright (c) 2026, Ronen Druker. All rights reserved.
#
# Build and install pam_tid_local (see pam_tid_local.c) and switch sudo's Touch ID to it, so
# sudo uses Touch ID at the Mac and the terminal password prompt over SSH, tmux included.
#
# - installs the module to /usr/local/lib/pam/pam_tid_local.so (root-owned, read-only)
# - rewrites /etc/pam.d/sudo_local: pam_tid -> pam_tid_local; pam_reattach is kept so Touch ID
#   still works in tmux at the Mac
# - removes a bare pam_tid line from /etc/pam.d/sudo, which would run before sudo_local and
#   pop the dialog regardless (macOS updates restore that file, without such a line)
# Both PAM files are backed up next to themselves with a .bak suffix first.
#
# Run it from a terminal at the Mac, or from a plain SSH session outside tmux: inside tmux over
# SSH, the sudo it needs would still raise the Touch ID dialog this replaces.
#
# Usage: install-pam-tid-local.sh

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "install-pam-tid-local: macOS only" >&2
  exit 1
fi

# directory of this script, where pam_tid_local.c lives
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# install location of the module
dest_dir=/usr/local/lib/pam
dest="${dest_dir}/pam_tid_local.so"
# scratch directory for the build, removed on exit
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# a universal bundle, ad-hoc signed by the linker like Homebrew's pam_reattach
clang -bundle -O2 -Wall -Wextra -Werror -arch arm64 -arch x86_64 \
  -o "${build}/pam_tid_local.so" "${here}/pam_tid_local.c" -lpam

sudo install -d -o root -g wheel -m 755 "$dest_dir"
sudo install -o root -g wheel -m 444 "${build}/pam_tid_local.so" "$dest"

# sudo_local: the include file macOS updates preserve
sudo_local=/etc/pam.d/sudo_local
reattach=/opt/homebrew/lib/pam/pam_reattach.so
{
  echo "# sudo_local: local config file which survives system update and is included for sudo"
  echo "# Touch ID at the Mac only; over SSH pam_tid_local defers to the password prompt"
  [[ -f "$reattach" ]] && echo "auth       optional       ${reattach} ignore_ssh"
  echo "auth       sufficient     ${dest}"
} >"${build}/sudo_local"
[[ -f "$sudo_local" ]] && sudo cp -p "$sudo_local" "${sudo_local}.bak"
sudo install -o root -g wheel -m 444 "${build}/sudo_local" "$sudo_local"

# /etc/pam.d/sudo: drop a bare pam_tid line that precedes the sudo_local include
sudo_pam=/etc/pam.d/sudo
if grep -qE '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' "$sudo_pam"; then
  sudo cp -p "$sudo_pam" "${sudo_pam}.bak"
  grep -vE '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' "$sudo_pam" >"${build}/sudo"
  sudo install -o root -g wheel -m 444 "${build}/sudo" "$sudo_pam"
fi

echo "installed ${dest}"
echo "--- ${sudo_local}"
cat "$sudo_local"
echo "--- ${sudo_pam}"
cat "$sudo_pam"
