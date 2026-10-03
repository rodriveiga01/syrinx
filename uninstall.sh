#!/bin/bash
# Syrinx uninstaller: stops the daemon and removes everything install.sh made.
# (Leaves Homebrew/pipx themselves alone.)
set -eu
say() { printf 'syrinx-uninstall: %s\n' "$*"; }
for label in com.syrinx.dictate com.user.whistle-dictate; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
rm -f "$HOME/.local/bin/syrinx" "$HOME/.local/bin/syrinx-transcribe"
rm -rf "$HOME/.config/syrinx" "$HOME/.cache/syrinx"
if command -v pipx >/dev/null 2>&1; then
  pipx uninstall cactus-needle 2>/dev/null || true
fi
say "Syrinx removed. (Re-grant nothing; permissions entries can stay.)"
