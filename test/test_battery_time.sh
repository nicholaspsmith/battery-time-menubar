#!/usr/bin/env bash
# Fixture-based tests for battery-time.30s.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/battery-time.5s.sh"
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

SUFFIX=" | size=11 sfsize=9"
check "on battery: just the ETA"             "$DISCHARGING" "1:52$SUFFIX"
check "on battery, no estimate: placeholder" "$NOEST"       "--:--$SUFFIX"
check "charging: bolt + time-to-full"        "$CHARGING"    ":bolt.fill: 1:20$SUFFIX"
check "charged: bolt only"                   "$CHARGED"     ":bolt.fill:$SUFFIX"
check "ac hold: bolt only"                   "$ACHOLD"      ":bolt.fill:$SUFFIX"

# dropdown content
has "dropdown: battery percentage"    "$DISCHARGING" "Battery: 22%"
has "dropdown: time-to-empty detail"  "$DISCHARGING" "1 hr 52 min until empty"
has "dropdown: charging detail"       "$CHARGING"    "Charging - 1 hr 20 min until full"
has "dropdown: charged detail"        "$CHARGED"     "Fully charged"
has "dropdown: battery settings link" "$DISCHARGING" "com.apple.Battery-Settings.extension"

exit $fail
