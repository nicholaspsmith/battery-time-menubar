#!/usr/bin/env bash
# Symlink the plugin into the SwiftBar plugin folder.
set -euo pipefail
PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/.config/SwiftBar}"
SRC="$(cd "$(dirname "$0")" && pwd)/battery-time.30s.sh"
mkdir -p "$PLUGIN_DIR"
ln -sf "$SRC" "$PLUGIN_DIR/battery-time.30s.sh"
echo "Linked $SRC -> $PLUGIN_DIR/battery-time.30s.sh"
echo "Reload SwiftBar to pick it up immediately (or wait for its refresh)."
