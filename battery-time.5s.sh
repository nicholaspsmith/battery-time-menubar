#!/usr/bin/env bash
# battery-time.5s.sh
# SwiftBar plugin: battery ETA (H:MM) in the menu bar, refreshed in place every 5s
# (plus instant updates from the power-watch.sh launchd agent on plug/unplug).
#   Menu bar:  on battery -> ETA only ("3:14"); plugged -> bolt (+ time-to-full).
#   Dropdown:  battery %, detailed time/status, and a Battery Settings link.
# In-place refresh keeps its position in menu-bar managers like Ice.
#
# <bitbar.title>Battery Time Remaining</bitbar.title>
# <bitbar.version>2.2</bitbar.version>
# <bitbar.desc>Battery time remaining (H:MM) with a details dropdown.</bitbar.desc>

export PATH="/usr/bin:/bin:$PATH"

SETTINGS_URL="x-apple.systempreferences:com.apple.Battery-Settings.extension"

batt="${PMSET_FIXTURE:-$(pmset -g batt)}"
line="$(printf '%s\n' "$batt" | grep 'InternalBattery')"

pct="$(printf '%s\n' "$line" | grep -Eo '[0-9]+%' | head -n1)"

# A meaningful ETA exists only while discharging or charging — "charged" reports
# a bogus "0:00 remaining", and "not charging" has no time at all.
time=""
case "$line" in
  *discharging*|*charging*)
    time="$(printf '%s\n' "$line" | grep -Eo '[0-9]{1,2}:[0-9]{2}' | head -n1)"
    ;;
esac

# Power source + human-readable status for the dropdown.
if printf '%s\n' "$batt" | grep -q "'AC Power'"; then
  plugged=1
  case "$line" in
    *"not charging"*) status="Plugged in (not charging)" ;;
    *charging*)       status="Charging" ;;
    *charged*)        status="Fully charged" ;;
    *)                status="Plugged in" ;;
  esac
else
  plugged=0
  status="On battery"
fi

# Humanize H:MM -> "X hr Y min" / "Y min".
human=""
if [ -n "$time" ]; then
  h=$((10#${time%%:*})); m=$((10#${time##*:}))
  if [ "$h" -gt 0 ]; then human="${h} hr ${m} min"; else human="${m} min"; fi
fi

# --- menu bar title ---
if [ "$plugged" = 1 ]; then
  if [ -n "$time" ]; then title=":bolt.fill: $time"; else title=":bolt.fill:"; fi
else
  title="${time:-"--:--"}"
fi
printf '%s | size=11 sfsize=9\n' "$title"

# --- dropdown: %, detail, Battery Settings link ---
if [ "$plugged" = 1 ]; then
  case "$status" in
    Charging) if [ -n "$human" ]; then detail="Charging - ${human} until full"; else detail="Charging"; fi ;;
    *)        detail="$status" ;;
  esac
else
  if [ -n "$human" ]; then detail="${human} until empty"; else detail="On battery (estimating...)"; fi
fi

echo "---"
printf 'Battery: %s\n' "${pct:-n/a}"
printf '%s\n' "$detail"
echo "---"
printf 'Open Battery Settings... | shell=/usr/bin/open param1=%s terminal=false\n' "$SETTINGS_URL"
