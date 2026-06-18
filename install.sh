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

echo "Reload SwiftBar to pick up the plugin (or it refreshes within 5s)."
