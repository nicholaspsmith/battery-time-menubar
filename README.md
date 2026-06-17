# battery-time-menubar

A tiny [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that restores the
estimated battery **time remaining** (`H:MM`) to the macOS menu bar — Apple
removed the always-visible estimate in Sierra (2016).

- Discharging → time to empty (e.g. `1:52`)
- Charging → time to full (e.g. `1:20`)
- Charged / on-AC hold / still calculating → nothing (the item hides)

Bare `H:MM` only — no glyphs, no percentage, no dropdown.

## Requirements

- macOS with a battery (laptop)
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (`brew install swiftbar`)

## Install

```sh
./install.sh
```

This symlinks `battery-time.30s.sh` into `~/.config/SwiftBar/` (override with
`SWIFTBAR_PLUGIN_DIR`). Reload SwiftBar, then ⌘-drag the item to sit beside the
battery icon.

## Test

```sh
./test/test_battery_time.sh
```

Fixture-driven: feeds captured `pmset -g batt` outputs via `PMSET_FIXTURE` and
checks the printed line.

## Uninstall

```sh
rm ~/.config/SwiftBar/battery-time.30s.sh
```
