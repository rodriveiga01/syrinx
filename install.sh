#!/bin/bash
# Syrinx installer: hold-to-talk dictation for macOS (on-device, no account).
#
# From a clone:   ./install.sh
# One-liner (after pushing): curl -fsSL https://raw.githubusercontent.com/rodriveiga01/syrinx/main/install.sh | bash
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.syrinx.dictate"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/syrinx"
CACHE_DIR="$HOME/.cache/syrinx"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

say() { printf 'syrinx-install: %s\n' "$*"; }
die() { printf 'syrinx-install: error: %s\n' "$*" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || die "macOS only."
[ "$(uname -m)" = "arm64" ] || say "warning: only tested on Apple silicon."

# 1. pipx ---------------------------------------------------------------
if ! command -v pipx >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || die "install Homebrew first: https://brew.sh"
  say "installing pipx..."
  brew install pipx
fi
pipx ensurepath >/dev/null 2>&1 || true
export PATH="$HOME/.local/bin:$PATH"

# 2. engine --------------------------------------------------------------
if pipx list 2>/dev/null | grep -q "cactus-needle"; then
  say "cactus-needle already installed, keeping it."
else
  say "installing cactus-needle (speech engine + mic support)..."
  pipx install "cactus-needle[mic]"
fi
VENV_PY=""
for c in "$HOME/Library/Application Support/pipx/venvs/cactus-needle/bin/python" \
         "$HOME/.local/share/pipx/venvs/cactus-needle/bin/python"; do
  if [ -x "$c" ]; then VENV_PY="$c"; break; fi
done
[ -n "$VENV_PY" ] || die "pipx venv python not found."
for mod in "pynput:pynput" "sounddevice:sounddevice" "Cocoa:pyobjc-framework-Cocoa" "Quartz:pyobjc-framework-Quartz"; do
  mod_name="${mod%%:*}"; pkg="${mod##*:}"
  if "$VENV_PY" -c "import $mod_name" 2>/dev/null; then
    say "python module $mod_name ok."
  else
    say "injecting $pkg into the engine venv..."
    pipx inject cactus-needle "$pkg" || pipx inject --force cactus-needle "$pkg"
  fi
done

# 3. model ---------------------------------------------------------------
mkdir -p "$CACHE_DIR"
if [ -f "$CACHE_DIR/whistle.cact" ]; then
  say "Whistle model already downloaded, keeping it."
else
  say "downloading Whistle model (16.9 MB)..."
  NEEDLE_BIN="$HOME/.local/bin/needle"
  [ -x "$NEEDLE_BIN" ] || die "needle CLI not found at $NEEDLE_BIN."
  "$NEEDLE_BIN" download whistle --out "$CACHE_DIR"
fi

# 4. scripts -------------------------------------------------------------
mkdir -p "$BIN_DIR" "$CONFIG_DIR"
cp "$REPO_DIR/bin/syrinx" "$REPO_DIR/bin/syrinx-transcribe" "$BIN_DIR/"
chmod +x "$BIN_DIR/syrinx" "$BIN_DIR/syrinx-transcribe"
cat > "$CONFIG_DIR/env" <<EOF
# written by Syrinx install.sh — do not edit by hand (re-run install.sh)
SYRINX_PYTHON="$VENV_PY"
SYRINX_MODEL="$CACHE_DIR/whistle.cact"
EOF
say "installed syrinx + syrinx-transcribe to $BIN_DIR."

# 5. LaunchAgent (start at login) -----------------------------------------
sed "s|%%HOME%%|$HOME|g" "$REPO_DIR/launchd/${LABEL}.plist" > "$PLIST"
for old in "$LABEL" "com.user.whistle-dictate"; do
  launchctl bootout "gui/$(id -u)/$old" 2>/dev/null || true
done
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 3
if launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q "state = running"; then
  say "dictation daemon running."
else
  die "daemon did not start — see $CACHE_DIR/syrinx.log"
fi

# 6. smoke test ------------------------------------------------------------
"$BIN_DIR/syrinx" --help >/dev/null
say "smoke test ok."

cat <<EOF

Done! Two manual steps (macOS requires your clicks):

  1) Grant Accessibility to the engine so it can see the hotkey:
       open -R "$VENV_PY"
     then drag the revealed file into
     System Settings → Privacy & Security → Accessibility → +  (toggle it on)

  2) Hold RIGHT OPTION and speak once — allow the Microphone prompt.

Use: click any text field, HOLD right-option, speak, release.
Logs: tail -f $CACHE_DIR/syrinx.log
Stop: launchctl bootout gui/$(id -u)/$LABEL
Uninstall: ./uninstall.sh  (from this repo)

Note: if ~/.local/bin is not on your PATH, restart your shell.
EOF
