# Battery time-remaining menu-bar item — design (as built)

**Date:** 2026-06-17, revised 2026-06-18
**Status:** implemented

> This records the final design. It evolved well beyond the original one-line
> brief through iteration; see the git history for the path.

## Goal

Restore an estimated battery **time remaining** to the macOS menu bar (Apple
removed the always-visible estimate in Sierra, 2016), with a state icon, a
details dropdown, and updates that feel as immediate as the native battery icon.

## Architecture

A SwiftBar plugin plus a launchd watcher, in a dedicated repo at
`~/Code/battery-time-menubar`, symlinked into `~/.config/SwiftBar/`.

- `battery-time.5s.sh` — the plugin. Parses `pmset -g batt`, prints the menu-bar
  title and a dropdown. Refreshed in place by SwiftBar every 5s.
- `power-watch.sh` — a launchd agent that listens to `pmset -g pslog` and, on
  each AC plug/unplug, calls `open swiftbar://refreshallplugins` for an instant
  in-place refresh.

## Menu-bar title

A native-style battery glyph: rounded body + nub, a **fill proportional to charge**,
the **`%` to its LEFT** and the **time to its RIGHT**. A *bisecting overlay* marks
state:

| State | Glyph |
| --- | --- |
| On battery | battery glyph (+ ETA), red fill ≤20% |
| Charging | battery glyph bisected by a **bolt** (+ time-to-full) |
| Low Power mode | battery glyph with a **yellow** fill |
| High Power mode | battery glyph bisected by a **💪 emoji** |

- The title is one tight image from `render-title.swift` (`--battery <pct>` with
  `--lead "<pct>%"`, `--text "<time>"`, and `--charging` / `--flex` for the
  overlay). A plain glyph emits as `templateImage=` so it auto-adapts to light/dark
  and spaces like the native icons (SwiftBar pads *text* items wider than images,
  issue #228). A colored fill (`--fill yellow|red`) or the 💪 overlay can't be a
  template, so it emits a colored `image=` and the plugin picks `--ink black|white`
  from the current appearance. Independent **icon / % / time** toggles via
  `set-display.sh`. Falls back to "`pct% [:bolt.fill:] time`" text when the helper
  isn't compiled or in tests (`BT_TITLE_TEXT=1`).
- Overlays are mutually exclusive: a charging **bolt** takes precedence over the
  High Power **💪** (charging is the more urgent status); fill color is yellow in
  Low Power, red on battery ≤20%.
- A meaningful ETA exists only while `discharging` or `charging`; `charged`
  reports a bogus `0:00 remaining`, so the ETA is gated on state.
- macOS reports `(no estimate)` for ~30–60s after unplug. To avoid showing `--:--`
  that whole time, on battery with no `pmset` estimate the plugin computes its own
  from `ioreg`: remaining `AppleRawCurrentCapacity` (mAh) ÷ |`InstantAmperage`|
  (mA). When the draw reads 0 (idle right after unplug) it falls back to a nominal
  ~12 W assumption (`current mA = 12000 / volts`).
- Only **our stop-gap** estimate is capped at that nominal (a near-zero idle draw
  projects an unrealistic 20h+). macOS's own estimate is shown as-is once it
  appears. Whole-hour times render as `8h` (menu bar) / `8 hr` (dropdown).
- The title is **never empty** — always at least the bolt or `--:--`. This is
  what keeps the item from disappearing and being re-added to Ice's hidden
  section.

## Dropdown

```
Automatic / Low Power / High Power   # energy-mode selector; active one checkmarked
---
Battery: 72%
3 hr 14 min until empty              # or "Charging - 1 hr 20 min until full", "Fully charged"
Health: 100% (11 cycles)             # ioreg AppleRawMaxCapacity/DesignCapacity + CycleCount
Using 12 W                           # ioreg Voltage x InstantAmperage; "Charging at N W" when plugged
Adapter: 140W USB-C Power Adapter     # ioreg AdapterDetails, when plugged
30°C · 13.1 V · 8318 / 8682 mAh       # temp (°C/°F toggle) · voltage · raw charge
Switch to °F                         # set-tempunit.sh persists the unit
---
24h on battery: 3h 12m (22%)         # from pmset -g log, background-cached (~10 min)
24h plugged in: 11h 9m (78%)
---
Open Battery Settings...             # shell=/usr/bin/open param1=<url> terminal=false
```

SwiftBar's own default dropdown items are hidden via `hide*` metadata.

Battery Settings URL: `x-apple.systempreferences:com.apple.Battery-Settings.extension`
(the `PowerPreferences.appex` pane on macOS 26; identifier verified against the
System Settings binary).

**Energy-mode selector:** `pmset powermode` (0 Automatic, 1 Low Power, 2 High
Power on Apple Silicon) needs root, so a tightly-scoped passwordless-sudo rule
(`/etc/sudoers.d/battery-time-powermode`, installed by
`install-powermode-sudoers.sh`) permits exactly `pmset -b/-c powermode 0|1|2`.

**24-hour usage:** `pmset -g log` has the source-change history but is slow
(~1.4s, ~53k lines), so the plugin recomputes the on-battery vs plugged split in
the **background** when the cache (`~/Library/Caches/battery-time-24h.cache`) is
older than ~10 min and renders from the cache (never blocking). Parsing uses perl
+ Time::Local (macOS awk lacks `mktime`); `compute_24h` is tested via
`PMSET_LOG_FIXTURE` + `BT_NOW` (`BT_COMPUTE_24H=1` prints raw seconds). The cache
line carries five fields: `batt ac minCharge highACsecs lowEpisodes`.

**Battery-longevity tips:** a section shown only when a trigger fires, from the
cache metrics + ioreg. Triggers: deep discharge (min ≤15% or ≥2 dips ≤20% in
24h), prolonged high charge (≥8h plugged at ≥95%), running warm (current temp
≥35°C), and cycle count near rated life (≥800 of ~1000). Rendered as a single
"Battery Life Tips" dropdown item that stashes the `💡` lines in a file and
opens them in a dialog (`show-tips.sh`), so the dropdown stays narrow.

## Updates / Ice positioning

- 5s in-place poll handles estimate drift.
- `power-watch.sh` (launchd KeepAlive agent) gives instant plug/unplug response
  by triggering the same in-place refresh.
- A SwiftBar **streamable** plugin was tried for event-driven updates and
  rejected: its `~~~` frame reset re-adds the status item, which Ice treats as a
  new item and moves to the hidden section on every update. In-place refresh
  (normal polling + refresh URL) does not have this problem.

## Testing

Inject captured `pmset -g batt` output via `PMSET_FIXTURE`; assert the menu-bar
title (first line) per state and grep the dropdown for the percentage, the
detail line, and the settings link.

## Out of scope (YAGNI)

- A dedicated app or custom Swift menu-bar binary
- Global menu-bar spacing changes (would affect all items)
