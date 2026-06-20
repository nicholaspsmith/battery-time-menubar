#!/usr/bin/env bash
# Fixture-based tests for battery-time.30s.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/battery-time.5s.sh"
export BT_TITLE_TEXT=1   # assert the text-form title (image bytes aren't deterministic)
export TEMPUNIT_FIXTURE=C # deterministic temperature unit for tests
export BT_SHOW_ICON=1 BT_SHOW_PCT=0 BT_SHOW_TIME=1  # deterministic menu-bar display prefs
export IOREG_FIXTURE='-'  # neutral ioreg (no battery data) unless a test overrides it
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

# Title fallback under BT_TITLE_TEXT: battery glyph -> "pct% time"; charging -> bolt.
check "on battery: glyph + ETA"       "$DISCHARGING" "22% 1:52"
check "on battery, no estimate"       "$NOEST"       "50% --:--"
check "charging: bolt + time-to-full" "$CHARGING"    ":bolt.fill: 1:20 | sfsize=9"
check "charged: glyph (pct)"          "$CHARGED"     "100%"
check "ac hold: glyph (pct)"          "$ACHOLD"      "80%"

# dropdown content
has "dropdown: battery percentage"    "$DISCHARGING" "Battery: 22%"
has "dropdown: time-to-empty detail"  "$DISCHARGING" "1 hr 52 min until empty"
has "dropdown: charging detail"       "$CHARGING"    "Charging - 1 hr 20 min until full"
has "dropdown: charged detail"        "$CHARGED"     "Fully charged"
has "dropdown: battery settings link" "$DISCHARGING" "com.apple.Battery-Settings.extension"

# energy-mode selector (POWERMODE_FIXTURE pins powermode: 0=auto,1=low,2=high)
has_pm "mode: Automatic active"    "$DISCHARGING" 0 "Automatic | sfimage=circle.inset.filled shell=/usr/bin/sudo param1=/usr/bin/pmset param2=-b param3=powermode param4=0"
has_pm "mode: Low Power inactive"  "$DISCHARGING" 0 "Low Power | sfimage=circle shell=/usr/bin/sudo param1=/usr/bin/pmset param2=-b param3=powermode param4=1"
has_pm "mode: High Power inactive" "$DISCHARGING" 0 "High Power | sfimage=circle shell=/usr/bin/sudo param1=/usr/bin/pmset param2=-b param3=powermode param4=2"
has_pm "mode: Low Power active"    "$DISCHARGING" 1 "Low Power | sfimage=circle.inset.filled shell=/usr/bin/sudo param1=/usr/bin/pmset param2=-b param3=powermode param4=1"
has_pm "mode: High Power active AC" "$CHARGING"   2 "High Power | sfimage=circle.inset.filled shell=/usr/bin/sudo param1=/usr/bin/pmset param2=-c param3=powermode param4=2"
has_pm "modes use -c on AC"        "$CHARGING"    0 "Low Power | sfimage=circle shell=/usr/bin/sudo param1=/usr/bin/pmset param2=-c param3=powermode param4=1"

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

# --- temperature unit toggle ---
has_u() {
  local name="$1" pf="$2" iof="$3" u="$4" needle="$5"
  if PMSET_FIXTURE="$pf" IOREG_FIXTURE="$iof" TEMPUNIT_FIXTURE="$u" "$SCRIPT" | grep -qF -- "$needle"; then
    printf 'ok   - %s\n' "$name"
  else
    printf 'FAIL - %s: output missing [%s]\n' "$name" "$needle"; fail=1
  fi
}
has_u "temp shown in Fahrenheit" "$CHARGING" "$IOREG_CHG" F "86°F · 13.1 V · 8318 / 8682 mAh"
has_u "toggle offers F when in C" "$CHARGING" "$IOREG_CHG" C "Switch to °F"
has_u "toggle command sets F"     "$CHARGING" "$IOREG_CHG" C "set-tempunit.sh param1=F"
has_u "toggle offers C when in F" "$CHARGING" "$IOREG_CHG" F "Switch to °C"

# --- 24h on-battery vs plugged history ---
# 3 events (UTC); window is the 24h before 2026-06-19 12:00:00Z:
#   06-18 06:00 AC, 06-18 18:00 Batt, 06-19 00:00 AC  ->  batt 6h, AC 18h.
LOG24='2026-06-18 06:00:00 -0000 Assertions Summary- Using AC(Charge: 90)
2026-06-18 18:00:00 -0000 Assertions Summary- Using Batt(Charge: 80)
2026-06-19 00:00:00 -0000 Assertions Summary- Using AC(Charge: 70)'
NOW24="$(TZ=UTC date -j -f '%Y-%m-%d %H:%M:%S' '2026-06-19 12:00:00' +%s 2>/dev/null)"
got24="$(TZ=UTC BT_COMPUTE_24H=1 BT_NOW="$NOW24" PMSET_LOG_FIXTURE="$LOG24" "$SCRIPT" 2>/dev/null)"
if [ "$got24" = "21600 64800 70 0 0" ]; then printf 'ok   - 24h compute: 6h batt / 18h AC + metrics\n'
else printf 'FAIL - 24h compute: expected [21600 64800 70 0 0] got [%s]\n' "$got24"; fail=1; fi

has_24h() {  # name cache-fixture needle
  if PMSET_FIXTURE="$DISCHARGING" BT_24H_CACHE_FIXTURE="$2" "$SCRIPT" | grep -qF -- "$3"; then
    printf 'ok   - %s\n' "$1"
  else printf 'FAIL - %s: missing [%s]\n' "$1" "$3"; fail=1; fi
}
has_24h "24h display: on-battery line" "21600 64800" "24h on battery: 6h 0m (25%)"
has_24h "24h display: plugged line"    "21600 64800" "24h plugged in: 18h 0m (75%)"

# --- battery longevity tips (cache fields: batt ac minCharge highACsecs lowEpisodes) ---
IOREG_HOT='    "CycleCount" = 11
    "DesignCapacity" = 8579
    "AppleRawMaxCapacity" = 8682
    "Voltage" = 13136
    "InstantAmperage" = 2917
    "Temperature" = 3600'
IOREG_OLD='    "CycleCount" = 850
    "DesignCapacity" = 8579
    "AppleRawMaxCapacity" = 8682
    "Voltage" = 13136
    "InstantAmperage" = 2917
    "Temperature" = 3026'
tip_has() {   # name pmset ioreg cache needle (in dropdown stdout)
  if PMSET_FIXTURE="$2" IOREG_FIXTURE="$3" BT_24H_CACHE_FIXTURE="$4" BT_TIPS_FILE=/dev/null "$SCRIPT" | grep -qF -- "$5"; then
    printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s: missing [%s]\n' "$1" "$5"; fail=1; fi
}
tip_hasnt() { # name pmset ioreg cache needle (must be absent from dropdown stdout)
  if PMSET_FIXTURE="$2" IOREG_FIXTURE="$3" BT_24H_CACHE_FIXTURE="$4" BT_TIPS_FILE=/dev/null "$SCRIPT" | grep -qF -- "$5"; then
    printf 'FAIL - %s: unexpected [%s]\n' "$1" "$5"; fail=1; else printf 'ok   - %s\n' "$1"; fi
}
tip_fires() { # name pmset ioreg cache needle (must be in the written tips file)
  local tf; tf="$(mktemp)"
  PMSET_FIXTURE="$2" IOREG_FIXTURE="$3" BT_24H_CACHE_FIXTURE="$4" BT_TIPS_FILE="$tf" "$SCRIPT" >/dev/null 2>&1
  if grep -qF -- "$5" "$tf"; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s: tip missing [%s]\n' "$1" "$5"; fail=1; fi
  rm -f "$tf"
}
tip_fires "tip: deep discharge"   "$DISCHARGING" "$IOREG_BAT" "1000 2000 9 0 3"      "You dropped to 9% recently (3× under 20%)"
tip_fires "tip: high charge"      "$CHARGING"    "$IOREG_CHG" "1000 2000 50 30000 0" "Plugged in near full 8h today"
tip_fires "tip: running warm"     "$CHARGING"    "$IOREG_HOT" "1000 2000 50 0 0"     "Battery is 36°C now"
tip_fires "tip: cycle near rated" "$CHARGING"    "$IOREG_OLD" "1000 2000 50 0 0"     "Cycle count 850 of ~1000"
tip_has   "tips item appears"     "$DISCHARGING" "$IOREG_BAT" "1000 2000 9 0 3"      "Battery Life Tips"
tip_hasnt "no tips item healthy"  "$CHARGING"    "$IOREG_CHG" "1000 2000 60 0 0"     "Battery Life Tips"
tip_hasnt "tip text not inline"   "$DISCHARGING" "$IOREG_BAT" "1000 2000 9 0 3"      "You dropped to 9%"

# --- menu-bar display toggles (icon / % / time) + native Energy Mode header ---
title_pref() {  # name pmset icon pct time expected-first-line
  local got; got="$(PMSET_FIXTURE="$2" BT_SHOW_ICON="$3" BT_SHOW_PCT="$4" BT_SHOW_TIME="$5" "$SCRIPT" | head -1)"
  if [ "$got" = "$6" ]; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s: expected [%s] got [%s]\n' "$1" "$6" "$got"; fail=1; fi
}
title_pref "display: glyph+time"    "$DISCHARGING" 1 0 1 "22% 1:52"
title_pref "display: glyph only"    "$DISCHARGING" 1 0 0 "22%"
title_pref "display: time only"     "$DISCHARGING" 0 0 1 "1:52"
title_pref "display: pct+time"      "$DISCHARGING" 0 1 1 "22% 1:52"
title_pref "display: none -> --:--" "$DISCHARGING" 0 0 0 "--:--"
has "energy mode header"    "$DISCHARGING" "Energy Mode"
has "display toggle items"  "$DISCHARGING" "set-display.sh param1=icon"

# gap estimate: when macOS reports "(no estimate)" on battery, compute our own
# (remaining mAh / discharge mA). 5000 mAh / 2500 mA = 2.0 h = 2:00.
NOEST_AMP="Now drawing from 'Battery Power'
 -InternalBattery-0 (id=1)	50%; discharging; (no estimate) present: true"
IOREG_EST='    "AppleRawCurrentCapacity" = 5000
    "InstantAmperage" = 18446744073709549116
    "DesignCapacity" = 8579
    "AppleRawMaxCapacity" = 8682
    "Voltage" = 12000'
got="$(PMSET_FIXTURE="$NOEST_AMP" IOREG_FIXTURE="$IOREG_EST" "$SCRIPT" | head -1)"
if [ "$got" = "50% 2:00" ]; then printf 'ok   - gap estimate (5000mAh / 2500mA -> 2:00)\n'
else printf 'FAIL - gap estimate: expected [50%% 2:00] got [%s]\n' "$got"; fail=1; fi

exit $fail
