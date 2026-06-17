#!/usr/bin/env bash
# battery-time.30s.sh
# SwiftBar plugin: estimated battery time remaining as H:MM in the menu bar.
# Time-to-empty while discharging, time-to-full while charging.
# Prints nothing (item hidden) when macOS has no estimate (charged / AC hold / calculating).
#
# <bitbar.title>Battery Time Remaining</bitbar.title>
# <bitbar.version>1.0</bitbar.version>
# <bitbar.desc>Shows estimated battery time remaining (H:MM) in the menu bar.</bitbar.desc>

export PATH="/usr/bin:/bin:$PATH"

batt="${PMSET_FIXTURE:-$(pmset -g batt)}"
line="$(printf '%s\n' "$batt" | grep 'InternalBattery')"

case "$line" in
  *discharging*|*charging*)
    time="$(printf '%s\n' "$line" | grep -Eo '[0-9]{1,2}:[0-9]{2}' | head -n1)"
    [ -n "$time" ] && printf '%s\n' "$time"
    ;;
esac
