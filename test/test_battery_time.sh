#!/usr/bin/env bash
# Fixture-based tests for battery-time.30s.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/battery-time.5s.sh"
export BT_TITLE_TEXT=1   # assert the text-form title (image bytes aren't deterministic)
fail=0

# check the menu-bar TITLE (first line; the rest of the output is the dropdown).
check() {
  local name="$1" fixture="$2" expected="$3" got
  got="$(PMSET_FIXTURE="$fixture" "$SCRIPT" | head -n1)"
  if [ "$got" = "$expected" ]; then
    printf 'ok   - %s\n' "$name"
  else
    printf 'FAIL - %s: expected [%s] got [%s]\n' "$name" "$expected" "$got"
    fail=1
  fi
}

# check that the full output (incl. dropdown) CONTAINS a substring.
has() {
  local name="$1" fixture="$2" needle="$3"
  if PMSET_FIXTURE="$fixture" "$SCRIPT" | grep -qF -- "$needle"; then
    printf 'ok   - %s\n' "$name"
  else
    printf 'FAIL - %s: output missing [%s]\n' "$name" "$needle"
    fail=1
  fi
}

# like has(), but also pins the current power mode (0/1/2) via POWERMODE_FIXTURE.
has_pm() {
  local name="$1" fixture="$2" pm="$3" needle="$4"
  if PMSET_FIXTURE="$fixture" POWERMODE_FIXTURE="$pm" "$SCRIPT" | grep -qF -- "$needle"; then
    printf 'ok   - %s\n' "$name"
  else
    printf 'FAIL - %s: output missing [%s]\n' "$name" "$needle"
    fail=1
  fi
}

DISCHARGING="Now drawing from 'Battery Power'
 -InternalBattery-0 (id=50921571)	22%; discharging; 1:52 remaining present: true"
CHARGING="Now drawing from 'AC Power'
 -InternalBattery-0 (id=50921571)	80%; charging; 1:20 remaining present: true"
NOEST="Now drawing from 'Battery Power'
 -InternalBattery-0 (id=50921571)	50%; discharging; (no estimate) present: true"
CHARGED="Now drawing from 'AC Power'
 -InternalBattery-0 (id=50921571)	100%; charged; 0:00 remaining present: true"
ACHOLD="Now drawing from 'AC Power'
 -InternalBattery-0 (id=50921571)	80%; AC attached; not charging present: true"

# On-battery titles are plain text (default font size); plugged titles carry the
# inline bolt sized down via sfsize=9.
BSUF=" | sfsize=9"
check "on battery: just the ETA"             "$DISCHARGING" "1:52"
check "on battery, no estimate: placeholder" "$NOEST"       "--:--"
check "charging: bolt + time-to-full"        "$CHARGING"    ":bolt.fill: 1:20$BSUF"
check "charged: bolt only"                   "$CHARGED"     ":bolt.fill:$BSUF"
check "ac hold: bolt only"                   "$ACHOLD"      ":bolt.fill:$BSUF"

# dropdown content
has "dropdown: battery percentage"    "$DISCHARGING" "Battery: 22%"
has "dropdown: time-to-empty detail"  "$DISCHARGING" "1 hr 52 min until empty"
has "dropdown: charging detail"       "$CHARGING"    "Charging - 1 hr 20 min until full"
has "dropdown: charged detail"        "$CHARGED"     "Fully charged"
has "dropdown: battery settings link" "$DISCHARGING" "com.apple.Battery-Settings.extension"

# energy-mode selector (POWERMODE_FIXTURE pins powermode: 0=auto,1=low,2=high)
has_pm "mode option: Automatic (battery)" "$DISCHARGING" 0 "Automatic | shell=/usr/bin/sudo param1=/usr/bin/pmset param2=-b param3=powermode param4=0"
has_pm "mode option: Low Power (battery)"  "$DISCHARGING" 0 "Low Power | shell=/usr/bin/sudo param1=/usr/bin/pmset param2=-b param3=powermode param4=1"
has_pm "mode option: High Power (battery)" "$DISCHARGING" 0 "High Power | shell=/usr/bin/sudo param1=/usr/bin/pmset param2=-b param3=powermode param4=2"
has_pm "Automatic checked when auto"       "$DISCHARGING" 0 "param4=0 terminal=false refresh=true checked=true"
has_pm "Low Power checked when low"        "$DISCHARGING" 1 "param4=1 terminal=false refresh=true checked=true"
has_pm "High Power checked when high"      "$CHARGING"    2 "param4=2 terminal=false refresh=true checked=true"
has_pm "modes use -c source on AC"         "$CHARGING"    0 "Low Power | shell=/usr/bin/sudo param1=/usr/bin/pmset param2=-c param3=powermode param4=1"

# the mode selector must be the FIRST dropdown section (before the Battery line)
out="$(PMSET_FIXTURE="$DISCHARGING" POWERMODE_FIXTURE=0 "$SCRIPT")"
a="$(printf '%s\n' "$out" | grep -n '^Automatic ' | head -1 | cut -d: -f1)"
b="$(printf '%s\n' "$out" | grep -n '^Battery: ' | head -1 | cut -d: -f1)"
if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then
  printf 'ok   - mode selector is first (Automatic@%s before Battery@%s)\n' "$a" "$b"
else
  printf 'FAIL - mode ordering: Automatic@%s Battery@%s\n' "$a" "$b"; fail=1
fi

# --- extra battery stats from ioreg (IOREG_FIXTURE pins the raw battery data) ---
has_io() {
  local name="$1" pf="$2" iof="$3" needle="$4"
  if PMSET_FIXTURE="$pf" IOREG_FIXTURE="$iof" "$SCRIPT" | grep -qF -- "$needle"; then
    printf 'ok   - %s\n' "$name"
  else
    printf 'FAIL - %s: output missing [%s]\n' "$name" "$needle"; fail=1
  fi
}
IOREG_CHG='    "CycleCount" = 11
    "DesignCapacity" = 8579
    "AppleRawMaxCapacity" = 8682
    "AppleRawCurrentCapacity" = 8318
    "Voltage" = 13136
    "InstantAmperage" = 2917
    "Temperature" = 3026
    "AdapterDetails" = {"Watts"=140,"Name"="140W USB-C Power Adapter"}'
# InstantAmperage here is the unsigned (two'\''s-complement) form of -2204 mA.
IOREG_BAT='    "CycleCount" = 11
    "DesignCapacity" = 8579
    "AppleRawMaxCapacity" = 8682
    "AppleRawCurrentCapacity" = 5000
    "Voltage" = 12000
    "InstantAmperage" = 18446744073709549412
    "Temperature" = 3100'

has_io "stat: health + cycles"    "$CHARGING"    "$IOREG_CHG" "Health: 100% (11 cycles)"
has_io "stat: charging watts"     "$CHARGING"    "$IOREG_CHG" "Charging at 38.3 W"
has_io "stat: adapter name"       "$CHARGING"    "$IOREG_CHG" "Adapter: 140W USB-C Power Adapter"
has_io "stat: extras (charging)"  "$CHARGING"    "$IOREG_CHG" "30°C · 13.1 V · 8318 / 8682 mAh"
has_io "stat: using watts (batt)" "$DISCHARGING" "$IOREG_BAT" "Using 26.4 W"
has_io "stat: extras (battery)"   "$DISCHARGING" "$IOREG_BAT" "31°C · 12.0 V · 5000 / 8682 mAh"

exit $fail
