# Battery time-remaining menu-bar item — design

**Date:** 2026-06-17
**Status:** approved design, pending implementation

## Goal

Show the estimated battery time remaining as a bare `H:MM` (e.g. `1:52`) in the
macOS menu bar, near the native battery icon. macOS removed the always-visible
"time remaining" menu-bar display in Sierra (2016), so this is restored via a
small SwiftBar plugin.

## Approach

A single shell-script SwiftBar plugin. No new app, no assets. Reuses the
existing SwiftBar setup (same folder as `vpn-dns-control.5s.sh`).

- **File:** `~/.config/SwiftBar/battery-time.30s.sh`
- **Refresh:** every 30s (the `.30s.` in the filename). The macOS estimate only
  updates roughly once a minute, so 30s is ample and cheap.
- **Data source:** `pmset -g batt`.
- Placed directly in `~/.config/SwiftBar/` — this is a plugin, so it does not
  violate the "only plugins live here" rule.

## Behavior

Branch on the battery state word, then extract the `H:MM` token.

| State (`pmset` state word)                        | Menu bar shows        |
| ------------------------------------------------- | --------------------- |
| `discharging`, has estimate                       | `1:52` (time to empty) |
| `charging`, has estimate                          | `1:20` (time to full)  |
| No estimate — `charged`, AC hold/`not charging`, or `(no estimate)` while calculating | *(prints nothing → item hidden)* |

Minimal by request: no glyphs, no percentage, no dropdown menu — only the
`H:MM` number. When there is no estimate, the script prints nothing, so SwiftBar
renders an empty (effectively hidden) item. This means the item appears and
disappears with charge state; that's the accepted tradeoff for the cleanest look.

## Parsing logic

1. Read `pmset -g batt` (or a fixture via `PMSET_FIXTURE` for testing).
2. Take the `InternalBattery` line. If absent (e.g. no battery), print nothing.
3. If the state is `discharging` or `charging`, extract the first
   `[0-9]{1,2}:[0-9]{2}` token and print it; otherwise print nothing.
4. The "has a time token" guard naturally handles every no-estimate case
   (`(no estimate)`, `not charging`, `charged`) by printing nothing.

Note: a `*charging*` substring match also matches `discharging` and
`not charging`. That's harmless here — `discharging` wants the same time
output, and `not charging` carries no time token so it prints nothing.

### Reference implementation

```bash
#!/usr/bin/env bash
# battery-time.30s.sh
# SwiftBar plugin: estimated battery time remaining as H:MM.
# Shows time-to-empty while discharging, time-to-full while charging.
# Prints nothing (item hidden) when macOS has no estimate.

export PATH="/usr/bin:/bin:$PATH"

batt="${PMSET_FIXTURE:-$(pmset -g batt)}"
line=$(printf '%s\n' "$batt" | grep 'InternalBattery')

case "$line" in
  *discharging*|*charging*)
    time=$(printf '%s\n' "$line" | grep -Eo '[0-9]{1,2}:[0-9]{2}' | head -n1)
    [ -n "$time" ] && printf '%s\n' "$time"
    ;;
esac
```

## Positioning

After SwiftBar loads the plugin, ⌘-drag the item to sit just left of the native
battery icon. macOS will not allow a third-party item *inside* the system
Control Center cluster, but immediately beside it is fine.

## Testing

Inject captured `pmset -g batt` outputs via the `PMSET_FIXTURE` env var and
assert the printed first line:

| Fixture state                          | Expected stdout |
| -------------------------------------- | --------------- |
| `discharging; 1:52 remaining`          | `1:52`          |
| `charging; 1:20 remaining`             | `1:20`          |
| `discharging; (no estimate)`           | *(empty)*       |
| `charged; 0:00 remaining`              | *(empty)*       |
| `AC attached; not charging`            | *(empty)*       |

Run these from the terminal before trusting the live menu-bar item.

## Out of scope (YAGNI)

- Glyphs / icons, percentage, charging indicator
- Dropdown menu, settings link
- Dedicated app or custom Swift menu-bar binary
