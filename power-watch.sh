#!/usr/bin/env bash
# power-watch.sh
# Instant power-state updates for battery-time. Watches macOS AC plug/unplug via
# `pmset -g pslog` (the IOKit power-source notification the native battery icon
# uses) and triggers an in-place SwiftBar refresh the moment it changes, so the
# menu-bar item updates immediately instead of waiting for its 5s poll.
# Runs as a launchd KeepAlive agent (see the accompanying .plist).

export PATH="/usr/bin:/bin:$PATH"

# `pmset -g pslog` blocks and prints a block on every power-source change; the
# "drawing from" header marks an AC plug/unplug. Refresh SwiftBar in place then.
pmset -g pslog 2>/dev/null | while IFS= read -r evt; do
  case "$evt" in
    *"drawing from"*) open -g "swiftbar://refreshallplugins" ;;
  esac
done
