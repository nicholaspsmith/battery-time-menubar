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
REPO_DIR="$(cd "$(dirname "$self")" 2>/dev/null && pwd)"
HELPER="$REPO_DIR/bin/render-title"

# Sum wall-clock seconds on battery vs AC over the last 24h from pmset -g log's
# "Using AC/Batt" events. perl (macOS awk lacks mktime). Prints "batt_secs ac_secs".
# Slow (pmset -g log is ~1.4s) — the live path runs this in the background + caches.
compute_24h() {
  local now="${BT_NOW:-$(date +%s)}"
  printf '%s\n' "${PMSET_LOG_FIXTURE:-$(pmset -g log 2>/dev/null)}" | BT_NOW="$now" perl -MTime::Local -e '
    my $now=$ENV{BT_NOW}; my $win=$now-86400; my(@T,@S,@C);
    while(<STDIN>){
      next unless /Using (AC|Batt)/; my $s=$1;
      next unless /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/;
      my $ts=timelocal($6,$5,$4,$3,$2-1,$1);
      my $c=(/Charge:\s*(\d+)/)?$1:-1;
      push @T,$ts; push @S,$s; push @C,$c;
    }
    my($b,$a,$minc,$hi,$lo,$pl)=(0,0,101,0,0,0);
    for my $i (0..$#T){ my $st=$T[$i]; my $en=($i<$#T)?$T[$i+1]:$now;
      next if $en<$win; $st=$win if $st<$win; $en=$now if $en>$now;
      my $d=$en-$st; $d=0 if $d<0;
      if($S[$i] eq "AC"){$a+=$d}else{$b+=$d}
      my $c=$C[$i];
      if($c>=0){ $minc=$c if $c<$minc;
        $hi+=$d if($S[$i] eq "AC" && $c>=95);
        if($c<=20 && !$pl){$lo++;$pl=1} elsif($c>25){$pl=0} } }
    $minc=-1 if $minc==101;
    printf "%d %d %d %d %d\n",$b,$a,$minc,$hi,$lo;'
}
if [ "${BT_COMPUTE_24H:-}" = 1 ]; then compute_24h; exit 0; fi

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

# Battery data from ioreg (one call; IOREG_FIXTURE seam). Captured here so both
# the menu-bar gap-estimate and the dropdown stats can use it.
ioreg_out="${IOREG_FIXTURE:-$(ioreg -rn AppleSmartBattery 2>/dev/null)}"
ival() { printf '%s\n' "$ioreg_out" | sed -n "s/^[[:space:]]*\"$1\" = \(-*[0-9][0-9]*\).*/\1/p" | head -n1; }
cyc="$(ival CycleCount)"; design="$(ival DesignCapacity)"; rawmax="$(ival AppleRawMaxCapacity)"
rawcur="$(ival AppleRawCurrentCapacity)"; volt_mv="$(ival Voltage)"; amp="$(ival InstantAmperage)"; temp100="$(ival Temperature)"
aname="$(printf '%s\n' "$ioreg_out" | sed -n 's/.*"AdapterDetails".*"Name"="\([^"]*\)".*/\1/p' | head -n1)"
awatts="$(printf '%s\n' "$ioreg_out" | sed -n 's/.*"AdapterDetails".*"Watts"=\([0-9][0-9]*\).*/\1/p' | head -n1)"

# macOS doesn't compute a time estimate for ~30-60s after unplug; fill that gap
# with our own (remaining mAh / discharge mA) so a time shows immediately.
if [ "$plugged" != 1 ] && [ -z "$time" ] && [ -n "$rawcur" ] && [ -n "$amp" ] && [ "${#amp}" -ge 11 ]; then
  dmag="$(echo "18446744073709551616 - $amp" | bc 2>/dev/null)"
  if [ -n "$dmag" ] && [ "$dmag" -gt 0 ] 2>/dev/null; then
    emins=$(( rawcur * 60 / dmag ))
    time="$(( emins / 60 )):$(printf '%02d' "$(( emins % 60 ))")"
  fi
fi

# Humanize H:MM -> "X hr Y min" / "Y min".
human=""
if [ -n "$time" ]; then
  h=$((10#${time%%:*})); m=$((10#${time##*:}))
  if [ "$h" -gt 0 ]; then human="${h} hr ${m} min"; else human="${m} min"; fi
fi

# --- menu bar title: bolt + time remaining (toggleable) ---
# A bolt icon + ETA, drawn as one tight monochrome image by render-title (falls
# back to inline ":bolt.fill: time" text). icon / % / time are independent toggles.
pct_num="${pct%\%}"
cur_pm="${POWERMODE_FIXTURE:-$(pmset -g | awk '/^[[:space:]]*powermode[[:space:]]/{print $2; exit}')}"
if [ "$plugged" = 1 ]; then mb_time="$time"; else mb_time="${time:-"--:--"}"; fi

# independent display toggles (env fixtures for tests; persisted by set-display.sh)
dpref() { local v; v="$(cat "$HOME/.config/battery-time/$1" 2>/dev/null)"; if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$2"; fi; }
show_icon="${BT_SHOW_ICON:-$(dpref icon 1)}"
show_pct="${BT_SHOW_PCT:-$(dpref pct 0)}"
show_time="${BT_SHOW_TIME:-$(dpref time 1)}"

# text part: pct% (optional) + time (optional)
mb_txt=""
[ "$show_pct" = 1 ] && [ -n "$pct_num" ] && mb_txt="${pct_num}%"
[ "$show_time" = 1 ] && [ -n "$mb_time" ] && mb_txt="${mb_txt:+$mb_txt }$mb_time"

title_fallback() {
  local f=""
  [ "$show_icon" = 1 ] && f=":bolt.fill:"
  [ -n "$mb_txt" ] && f="${f:+$f }$mb_txt"
  [ -z "$f" ] && f="--:--"
  if [ "$show_icon" = 1 ]; then printf '%s | sfsize=9\n' "$f"; else printf '%s\n' "$f"; fi
}

if [ -x "$HELPER" ] && [ -z "${BT_TITLE_TEXT:-}" ]; then
  targs=()
  [ "$show_icon" = 1 ] && targs+=(--bolt)
  if [ -n "$mb_txt" ]; then targs+=(--text "$mb_txt")
  elif [ "$show_icon" != 1 ]; then targs+=(--text "--:--"); fi
  b64="$("$HELPER" "${targs[@]}" 2>/dev/null)"
  if [ -n "$b64" ]; then printf '| templateImage=%s\n' "$b64"; else title_fallback; fi
else
  title_fallback
fi

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
# (cur_pm is already computed in the menu-bar title section above.)
if [ "$plugged" = 1 ]; then pm_src="-c"; else pm_src="-b"; fi

mode_item() {  # <powermode value> <label>
  local val="$1" label="$2" sym="circle"
  [ "$cur_pm" = "$val" ] && sym="circle.inset.filled"
  printf '%s | sfimage=%s shell=/usr/bin/sudo param1=/usr/bin/pmset param2=%s param3=powermode param4=%s terminal=false refresh=true\n' \
    "$label" "$sym" "$pm_src" "$val"
}

echo "---"
printf 'Energy Mode | size=12 color=#8e8e93\n'
mode_item 0 "Automatic"
mode_item 1 "Low Power"
mode_item 2 "High Power"
# --- extra battery stats (ioreg captured above) ---
health_line=""; power_line=""; adapter_line=""; extras_line=""
if [ -n "$rawmax" ] && [ -n "$design" ] && [ "$design" -gt 0 ]; then
  h=$(( rawmax * 100 / design )); [ "$h" -gt 100 ] && h=100
  health_line="Health: ${h}%${cyc:+ (${cyc} cycles)}"
fi
if [ -n "$volt_mv" ] && [ -n "$amp" ]; then
  # InstantAmperage is unsigned 64-bit; the ~20-digit values are negative (discharge).
  if [ "${#amp}" -ge 11 ]; then mag="$(echo "18446744073709551616 - $amp" | bc 2>/dev/null)"; chg=0; else mag="$amp"; chg=1; fi
  w="$(echo "scale=1; $volt_mv * $mag / 1000000" | bc 2>/dev/null)"
  if [ "$plugged" = 1 ] && [ "$chg" = 1 ]; then power_line="Charging at ${w} W"
  elif [ "$plugged" != 1 ]; then power_line="Using ${w} W"; fi
fi
if [ "$plugged" = 1 ] && { [ -n "$aname" ] || [ -n "$awatts" ]; }; then
  adapter_line="Adapter: ${aname:-${awatts} W}"
fi
# temperature unit preference (TEMPUNIT_FIXTURE seam; persisted by set-tempunit.sh)
tunit="${TEMPUNIT_FIXTURE:-$(cat "$HOME/.config/battery-time/tempunit" 2>/dev/null)}"; [ "$tunit" = "F" ] || tunit="C"
temp_disp=""; parts=""
if [ -n "$temp100" ]; then
  c=$(( temp100 / 100 ))
  if [ "$tunit" = "F" ]; then temp_disp="$(( c * 9 / 5 + 32 ))°F"; else temp_disp="${c}°C"; fi
  parts="$temp_disp"
fi
[ -n "$volt_mv" ] && { v="$(echo "scale=1; $volt_mv / 1000" | bc 2>/dev/null)"; parts="${parts:+$parts · }${v} V"; }
[ -n "$rawcur" ] && [ -n "$rawmax" ] && parts="${parts:+$parts · }${rawcur} / ${rawmax} mAh"
extras_line="$parts"
temp_toggle_line=""
if [ -n "$temp100" ]; then
  if [ "$tunit" = "C" ]; then temp_toggle_line="Switch to °F | shell=$REPO_DIR/set-tempunit.sh param1=F terminal=false refresh=true"
  else temp_toggle_line="Switch to °C | shell=$REPO_DIR/set-tempunit.sh param1=C terminal=false refresh=true"; fi
fi

# 24h on-battery vs plugged usage (cached; background recompute when stale).
usage24="${BT_24H_CACHE_FIXTURE:-}"
if [ -z "$usage24" ]; then
  CACHE24="$HOME/Library/Caches/battery-time-24h.cache"
  if [ ! -f "$CACHE24" ] || [ -n "$(find "$CACHE24" -mmin +10 2>/dev/null)" ]; then
    ( compute_24h > "$CACHE24.tmp.$$" 2>/dev/null && mv -f "$CACHE24.tmp.$$" "$CACHE24" ) >/dev/null 2>&1 &
  fi
  usage24="$(cat "$CACHE24" 2>/dev/null)"
fi
b24=""; a24=""; minc24=""; highac24=""; loweps24=""
[ -n "$usage24" ] && read -r b24 a24 minc24 highac24 loweps24 _ <<< "$usage24"
usage24_batt=""; usage24_ac=""
if [ -n "$b24" ] && [ -n "$a24" ]; then
  tot24=$(( b24 + a24 ))
  if [ "$tot24" -gt 0 ]; then
    pb=$(( (b24 * 100 + tot24 / 2) / tot24 )); pa=$(( 100 - pb ))
    usage24_batt="24h on battery: $(( b24 / 3600 ))h $(( (b24 % 3600) / 60 ))m (${pb}%)"
    usage24_ac="24h plugged in: $(( a24 / 3600 ))h $(( (a24 % 3600) / 60 ))m (${pa}%)"
  fi
fi

# --- battery longevity tips (shown only when a trigger fires) ---
tips=""
add_tip() { if [ -z "$tips" ]; then tips="💡 $1"; else tips="$tips"$'\n'"💡 $1"; fi; }
if [ -n "$minc24" ] && [ "$minc24" -ge 0 ] && { [ "$minc24" -le 15 ] || { [ -n "$loweps24" ] && [ "$loweps24" -ge 2 ]; }; }; then
  add_tip "You dropped to ${minc24}% recently${loweps24:+ (${loweps24}× under 20%)}. Recharge before ~20% — deep discharges add wear."
fi
if [ -n "$highac24" ] && [ "$highac24" -ge 28800 ]; then
  add_tip "Plugged in near full $(( highac24 / 3600 ))h today. Sitting at high charge ages Li-ion — enable Optimized Charging / 80% limit."
fi
if [ -n "$temp100" ] && [ "$(( temp100 / 100 ))" -ge 35 ]; then
  add_tip "Battery is ${temp_disp} now. Heat is the top cause of aging — improve airflow, ease load while charging."
fi
if [ -n "$cyc" ] && [ "$cyc" -ge 800 ]; then
  add_tip "Cycle count ${cyc} of ~1000 rated — nearing rated life; some capacity loss is expected."
fi

echo "---"
printf 'Battery: %s\n' "${pct:-n/a}"
printf '%s\n' "$detail"
[ -n "$health_line" ]  && printf '%s\n' "$health_line"
[ -n "$power_line" ]   && printf '%s\n' "$power_line"
[ -n "$adapter_line" ] && printf '%s\n' "$adapter_line"
[ -n "$extras_line" ]  && printf '%s\n' "$extras_line"
[ -n "$temp_toggle_line" ] && printf '%s\n' "$temp_toggle_line"
if [ -n "$usage24_batt" ]; then
  echo "---"
  printf '%s\n' "$usage24_batt"
  printf '%s\n' "$usage24_ac"
fi
if [ -n "$tips" ]; then
  # Keep the dropdown narrow: stash the tip text in a file and show one item that
  # opens it in a dialog (show-tips.sh) rather than printing the long lines inline.
  printf '%s\n' "$tips" > "${BT_TIPS_FILE:-$HOME/Library/Caches/battery-time-tips.txt}" 2>/dev/null
  echo "---"
  printf 'Battery Life Tips | shell=%s/show-tips.sh terminal=false\n' "$REPO_DIR"
fi
ic=""; [ "$show_icon" = 1 ] && ic=" checked=true"
pc=""; [ "$show_pct" = 1 ] && pc=" checked=true"
tc=""; [ "$show_time" = 1 ] && tc=" checked=true"
echo "---"
echo "Menu bar shows..."
printf -- '-- Battery icon | shell=%s/set-display.sh param1=icon terminal=false refresh=true%s\n' "$REPO_DIR" "$ic"
printf -- '-- Percentage | shell=%s/set-display.sh param1=pct terminal=false refresh=true%s\n' "$REPO_DIR" "$pc"
printf -- '-- Time remaining | shell=%s/set-display.sh param1=time terminal=false refresh=true%s\n' "$REPO_DIR" "$tc"
echo "---"
printf 'Open Battery Settings... | shell=/usr/bin/open param1=%s terminal=false\n' "$SETTINGS_URL"
