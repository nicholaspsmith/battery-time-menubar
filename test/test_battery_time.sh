#!/usr/bin/env bash
# Fixture-based tests for battery-time.30s.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/battery-time.30s.sh"
fail=0

check() {
  local name="$1" fixture="$2" expected="$3" got
  got="$(PMSET_FIXTURE="$fixture" "$SCRIPT")"
  if [ "$got" = "$expected" ]; then
    printf 'ok   - %s\n' "$name"
  else
    printf 'FAIL - %s: expected [%s] got [%s]\n' "$name" "$expected" "$got"
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

check "discharging shows time-to-empty" "$DISCHARGING" "1:52"
check "charging shows time-to-full"     "$CHARGING"    "1:20"
check "no estimate prints nothing"      "$NOEST"       ""
check "charged prints nothing"          "$CHARGED"     ""
check "ac hold prints nothing"          "$ACHOLD"      ""

exit $fail
