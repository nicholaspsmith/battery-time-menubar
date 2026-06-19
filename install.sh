#!/usr/bin/env bash
# Install battery-time: symlink the SwiftBar plugin and load the power-watch
# launchd agent (instant menu-bar refresh on AC plug/unplug).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/.config/SwiftBar}"

# --- SwiftBar plugin ---
chmod +x "$SRC_DIR/battery-time.5s.sh"
mkdir -p "$PLUGIN_DIR"
rm -f "$PLUGIN_DIR/battery-time.30s.sh" "$PLUGIN_DIR/battery-time.sh"  # prior installs
ln -sf "$SRC_DIR/battery-time.5s.sh" "$PLUGIN_DIR/battery-time.5s.sh"
echo "Linked plugin -> $PLUGIN_DIR/battery-time.5s.sh"

# --- compile the menu-bar image renderer (optional; plugin falls back to text) ---
if command -v swiftc >/dev/null 2>&1; then
  mkdir -p "$SRC_DIR/bin"
  if swiftc -O "$SRC_DIR/render-title.swift" -o "$SRC_DIR/bin/render-title" 2>/dev/null; then
    echo "Compiled menu-bar image renderer (tight spacing)."
  else
    echo "WARNING: render-title.swift failed to compile; menu bar uses the wider text form."
  fi
else
  echo "NOTE: swiftc not found; menu bar uses the wider text form. Install Xcode CLT for tight rendering."
fi

# --- power-watch launchd agent ---
LABEL="com.nicholassmith.battery-time-power-watch"
WATCH="$SRC_DIR/power-watch.sh"
LOG="$HOME/Library/Logs/battery-time-power-watch.log"
LA="$HOME/Library/LaunchAgents"
PLIST="$LA/$LABEL.plist"
chmod +x "$WATCH"
mkdir -p "$LA"
sed -e "s|__WATCH_SCRIPT__|$WATCH|g" -e "s|__LOG__|$LOG|g" "$SRC_DIR/$LABEL.plist" > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST"
echo "Loaded launchd agent $LABEL (instant plug/unplug refresh)."

# --- Low Power Mode toggle: one-time passwordless-sudo rule ---
if [ ! -f /etc/sudoers.d/battery-time-powermode ]; then
  echo "NOTE: the dropdown's Low Power Mode toggle needs a one-time setup:"
  echo "    sudo $SRC_DIR/install-powermode-sudoers.sh"
fi

echo "Reload SwiftBar to pick up the plugin (or it refreshes within 5s)."
