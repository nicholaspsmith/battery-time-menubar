# battery-time-menubar

A tiny [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that restores the
estimated battery **time remaining** to the macOS menu bar — Apple removed the
always-visible estimate in Sierra (2016) — with instant plug/unplug updates and
a details dropdown.

## What it shows

**Menu bar** — a **bolt** icon + the time remaining, drawn as one tight monochrome
image by the compiled `render-title` helper (auto-adapts to light/dark), so it
spaces like the native icons.

- Time is to-empty on battery, to-full while charging; bolt alone when there's no
  estimate (e.g. fully charged).
- Independent **icon / percentage / time** toggles ("Menu bar shows…" in the dropdown).
- Right after unplug macOS takes ~30–60s to compute its time estimate; until then
  the plugin shows its **own** — from the measured discharge current, or a nominal
  ~12 W assumption when the laptop is idle (0 mA draw) — so a time appears
  immediately instead of `--:--`. Rough/jumpy at first; the measured, then macOS,
  estimate takes over as real draw appears.
- Falls back to ":bolt.fill: time" text if `render-title` isn't compiled. Always
  renders something, so it keeps its position in menu-bar managers like Ice.

**Dropdown** (click the item; SwiftBar's own default items are hidden — Option-click reveals them):

- A native-style **Energy Mode** section at the top — Automatic / Low Power /
  High Power, the active one checkmarked; selecting one sets `pmset powermode`
- Battery percentage
- A detailed status line — `3 hr 14 min until empty`, `Charging - 1 hr 20 min until full`, `Fully charged`, …
- Extra stats (one `ioreg` call): health + cycle count, live power draw (V×A),
  adapter wattage, and temperature (with a °C/°F toggle) / voltage / raw charge (mAh)
- 24-hour usage — time on battery vs plugged in, parsed from `pmset -g log`
  (which is slow, so it's recomputed in the background and cached ~10 min — the
  scrape never blocks a refresh)
- Battery-longevity **tips** — a "Battery Life Tips" item (shown only when a
  trigger fires: deep discharges, prolonged high charge, running warm, or cycle
  count near rated life) that opens a dialog with the advice (keeps the dropdown narrow)
- **Menu bar shows…** — toggle the battery icon / percentage / time independently
- **Open Battery Settings...** — opens the Battery pane in System Settings

## Updates

- Refreshes in place every 5s (estimate drift).
- **Instant on plug/unplug** via `power-watch.sh`, a launchd agent that listens
  to `pmset -g pslog` (the IOKit power-source notification the native battery
  icon uses) and triggers SwiftBar's in-place refresh the moment AC changes.
  In-place refresh keeps the Ice position (unlike a SwiftBar *streamable*
  plugin, whose frame resets re-add the item and bounce it to Ice's hidden
  section).

## Requirements

- macOS laptop
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (`brew install swiftbar`)
- Xcode Command Line Tools (`swiftc`) for the tight image rendering — optional;
  without it the menu-bar title falls back to (slightly wider) text

## Install

```sh
./install.sh
```

This:
1. Symlinks `battery-time.5s.sh` into `~/.config/SwiftBar/` (override with `SWIFTBAR_PLUGIN_DIR`).
2. Installs and loads the `com.nicholassmith.battery-time-power-watch` launchd
   agent (logs to `~/Library/Logs/battery-time-power-watch.log`).

Then ⌘-drag the item next to the battery icon.

### Energy mode selector (one-time setup)

Changing the energy mode runs `pmset powermode`, which requires root. To make the
selector one-click with no password prompt, install a tightly-scoped sudoers rule
(permits only `pmset -b/-c powermode 0|1|2` — nothing else):

```sh
sudo ./install-powermode-sudoers.sh
```

On Apple Silicon the energy mode is `powermode` (0 = Automatic, 1 = Low Power,
2 = High Power). The selector sets the mode for the **current** power source, so
changing it on battery won't disturb a High Power-on-AC setting. (High Power only
takes effect where the hardware supports it — generally on AC.)

## Test

```sh
./test/test_battery_time.sh
```

Fixture-driven (via `PMSET_FIXTURE`): checks the menu-bar title and dropdown
content for each power state, with no real battery required.

## Uninstall

```sh
launchctl bootout "gui/$(id -u)/com.nicholassmith.battery-time-power-watch"
rm ~/Library/LaunchAgents/com.nicholassmith.battery-time-power-watch.plist
rm ~/.config/SwiftBar/battery-time.5s.sh
sudo rm -f /etc/sudoers.d/battery-time-powermode
```

## Files

- `battery-time.5s.sh` — the SwiftBar plugin (menu-bar title + dropdown)
- `power-watch.sh` — `pmset -g pslog` watcher for instant plug/unplug refresh
- `com.nicholassmith.battery-time-power-watch.plist` — launchd agent template
- `install.sh` — installer (plugin symlink + launchd agent)
- `install-powermode-sudoers.sh` — one-time passwordless-sudo rule for the toggle
- `render-title.swift` — compiles to `bin/render-title`; draws the bolt + text (battery-glyph mode also available)
- `set-tempunit.sh` — persists the dropdown °C/°F temperature unit
- `set-display.sh` — toggles the menu-bar icon / percentage / time prefs
- `show-tips.sh` — opens the current battery-longevity tips in a dialog
- `test/test_battery_time.sh` — fixture tests
- `docs/` — design notes and plan
