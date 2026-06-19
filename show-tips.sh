#!/usr/bin/env bash
# show-tips.sh — pop the current battery-longevity tips in a dialog.
# Called by the dropdown's "Battery Life Tips" item; reads the file the plugin wrote.
f="${BT_TIPS_FILE:-$HOME/Library/Caches/battery-time-tips.txt}"
[ -f "$f" ] || exit 0
tips="$(cat "$f")"
[ -n "$tips" ] || exit 0
/usr/bin/osascript - "$tips" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display alert "Battery Life Tips" message (item 1 of argv) as informational
end run
APPLESCRIPT
