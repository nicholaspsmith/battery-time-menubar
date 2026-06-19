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

| Power state | Title |
| --- | --- |
| On battery, has estimate | `3:14` (time to empty) |
| On battery, no estimate | `--:--` |
| Charging, has estimate | bolt + `1:20` (time to full) |
| Charged / plugged-in / not-charging | bolt only |

- The title is rendered as a tight transparent **template image** by the compiled
  `render-title.swift` helper (bolt `bolt.fill` drawn into the image), emitted as
  `| templateImage=<base64>` with an empty title — so it sits as closely as the
  icon-based menu-bar items. SwiftBar pads *text* items wider than image items
  (issue #228), which is why our lone text item looked over-padded. It falls back
  to a text title (inline `:bolt.fill:` + `sfsize=9`, default-size digits) when
  the helper isn't compiled or in tests (`BT_TITLE_TEXT=1`).
- A meaningful ETA exists only while `discharging` or `charging`; `charged`
  reports a bogus `0:00 remaining`, so the ETA is gated on state.
- The title is **never empty** — always at least the bolt or `--:--`. This is
  what keeps the item from disappearing and being re-added to Ice's hidden
  section.

## Dropdown

```
Battery: 72%
3 hr 14 min until empty           # or "Charging - 1 hr 20 min until full", "Fully charged", ...
---
Open Battery Settings...          # shell=/usr/bin/open param1=<url> terminal=false
```

Battery Settings URL: `x-apple.systempreferences:com.apple.Battery-Settings.extension`
(the `PowerPreferences.appex` pane on macOS 26; identifier verified against the
System Settings binary).

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

- Battery-level glyphs / percentage in the menu-bar title (dropped in favor of a
  bolt-or-ETA title; the percentage lives in the dropdown)
- A dedicated app or custom Swift menu-bar binary
- Global menu-bar spacing changes (would affect all items)
