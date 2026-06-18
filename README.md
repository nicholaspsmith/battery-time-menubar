# battery-time-menubar

A tiny [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that restores the
estimated battery **time remaining** to the macOS menu bar — Apple removed the
always-visible estimate in Sierra (2016) — with instant plug/unplug updates and
a details dropdown.

## What it shows

**Menu bar:**

| State | Shows |
| --- | --- |
| On battery | the ETA only, e.g. `3:14` (time to empty) |
| On battery, still estimating | `--:--` |
| Charging | bolt + time-to-full, e.g. bolt `1:20` |
| Charged / plugged in (no estimate) | bolt only |

The bolt is the SF Symbol `bolt.fill`, embedded inline and sized with `sfsize`,
so it takes the menu-bar label color and adapts to light/dark mode. The item
always renders something, so it never disappears and keeps its position in
menu-bar managers like Ice (a vanishing item gets re-added to Ice's hidden
section).

**Dropdown** (click the item):

- Battery percentage
- A detailed status line — `3 hr 14 min until empty`, `Charging - 1 hr 20 min until full`, `Fully charged`, …
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

## Install

```sh
./install.sh
```

This:
1. Symlinks `battery-time.5s.sh` into `~/.config/SwiftBar/` (override with `SWIFTBAR_PLUGIN_DIR`).
2. Installs and loads the `com.nicholassmith.battery-time-power-watch` launchd
   agent (logs to `~/Library/Logs/battery-time-power-watch.log`).

Then ⌘-drag the item next to the battery icon.

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
```

## Files

- `battery-time.5s.sh` — the SwiftBar plugin (menu-bar title + dropdown)
- `power-watch.sh` — `pmset -g pslog` watcher for instant plug/unplug refresh
- `com.nicholassmith.battery-time-power-watch.plist` — launchd agent template
- `install.sh` — installer (plugin symlink + launchd agent)
- `test/test_battery_time.sh` — fixture tests
- `docs/` — design notes and plan
