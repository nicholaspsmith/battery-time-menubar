#!/usr/bin/env bash
# battery-time.5s.sh
# SwiftBar plugin: battery ETA (H:MM) in the menu bar, refreshed in place every 5s
# (plus instant updates from the power-watch.sh launchd agent on plug/unplug).
#   Menu bar:  on battery -> ETA only ("3:14"); plugged -> bolt (+ time-to-full).
#   Dropdown:  battery %, detailed time/status, and a Battery Settings link.
# In-place refresh keeps its position in menu-bar managers like Ice.
#
# <bitbar.title>Battery Time Remaining</bitbar.title>
# <bitbar.version>2.3</bitbar.version>
# <bitbar.desc>Battery time remaining (H:MM) with a details dropdown.</bitbar.desc>
# Hide SwiftBar's default dropdown items (Option+Click still reveals them).
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

export PATH="/usr/bin:/bin:$PATH"

# Locate the compiled menu-bar image renderer (next to the real script, even when
# this plugin is reached via a symlink in the SwiftBar plugin folder).
self="$0"; [ -L "$self" ] && self="$(readlink "$self")"
HELPER="$(cd "$(dirname "$self")" 2>/dev/null && pwd)/bin/render-title"

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
# Rendered as a tight transparent template image (matches the icon-based items'
# spacing — SwiftBar pads text items wider). Falls back to text if the renderer
# isn't compiled or BT_TITLE_TEXT is set (tests use the text form).
if [ "$plugged" = 1 ]; then mb_text="$time"; mb_bolt=1; else mb_text="${time:-"--:--"}"; mb_bolt=0; fi

emit_title() {  # <text> <bolt:0|1>
  local txt="$1" bolt="$2" b64=""
  if [ -x "$HELPER" ] && [ -z "${BT_TITLE_TEXT:-}" ]; then
    if [ "$bolt" = 1 ]; then b64="$("$HELPER" "$txt" --bolt 2>/dev/null)"; else b64="$("$HELPER" "$txt" 2>/dev/null)"; fi
    if [ -n "$b64" ]; then printf '| templateImage=%s\n' "$b64"; return; fi
  fi
  # text fallback (also the form exercised by tests)
  if [ "$bolt" = 1 ]; then
    if [ -n "$txt" ]; then printf ':bolt.fill: %s | sfsize=9\n' "$txt"; else printf ':bolt.fill: | sfsize=9\n'; fi
  else
    printf '%s\n' "$txt"
  fi
}
emit_title "$mb_text" "$mb_bolt"

# --- dropdown: %, detail, Battery Settings link ---
if [ "$plugged" = 1 ]; then
  case "$status" in
    Charging) if [ -n "$human" ]; then detail="Charging - ${human} until full"; else detail="Charging"; fi ;;
    *)        detail="$status" ;;
  esac
else
  if [ -n "$human" ]; then detail="${human} until empty"; else detail="On battery (estimating...)"; fi
fi

# Energy-mode selector (first in the dropdown). powermode: 0 Automatic, 1 Low
# Power, 2 High Power. The active mode is checkmarked; selecting one sets it for
# the current power source via passwordless sudo (install-powermode-sudoers.sh).
cur_pm="${POWERMODE_FIXTURE:-$(pmset -g | awk '/^[[:space:]]*powermode[[:space:]]/{print $2; exit}')}"
if [ "$plugged" = 1 ]; then pm_src="-c"; else pm_src="-b"; fi

mode_item() {  # <powermode value> <label>
  local val="$1" label="$2" chk=""
  [ "$cur_pm" = "$val" ] && chk=" checked=true"
  printf '%s | shell=/usr/bin/sudo param1=/usr/bin/pmset param2=%s param3=powermode param4=%s terminal=false refresh=true%s\n' \
    "$label" "$pm_src" "$val" "$chk"
}

echo "---"
mode_item 0 "Automatic"
mode_item 1 "Low Power"
mode_item 2 "High Power"
echo "---"
printf 'Battery: %s\n' "${pct:-n/a}"
printf '%s\n' "$detail"
echo "---"
printf 'Open Battery Settings... | shell=/usr/bin/open param1=%s terminal=false\n' "$SETTINGS_URL"
