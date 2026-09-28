# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [1.1.0] - 2026-09-27

- With the face on, the battery is taller (17pt instead of 13pt) to make more of the menu bar's height and give the face room
- The battery face's mood follows the charge: a smile from 60%, a flat "meh" line from 35%, a slight frown below that, and a full frown when low
- The battery face stays visible across the empty part of the battery: where it crosses past the charge it is drawn in the menu-bar ink instead of cut out; over a Low Power Mode yellow fill it is drawn in black
- While charging, the face stays (instead of being replaced by the bolt): the fill turns green and it grins with happy ^ ^ eyes
- Plugged in but not charging (full, or macOS holding the charge at a limit), the battery becomes a smiling plug

## [1.0.1] - 2026-09-23

- chore: regenerate the menu-bar icon image

## [1.0.0] - 2026-09-23

- feat: the menu shows the version it was built from
- LICENSE: name the copyright holder above the MPL text
- License: Mozilla Public License 2.0
- docs: document the --login flag
- feat: --login on|off|status from the command line
- docs: Curtain is now Barn
- docs: Apollo Monitor described without the vendor name
- feat: the battery frowns when low, drawn in ink over the empty body
- docs: drop instructions that assume other software the reader may not use
- docs: the character menu-bar icon, rendered from code, and what its states mean
- fix: smaller battery face that stays inside the outline
- feat: a face on the battery glyph (Menu bar shows ▸ Battery face)
- feat: app icon from the Menubarn mascot
- docs: why a standalone app beats a SwiftBar plugin
- docs: README leads with the standalone app; SwiftBar plugin is the fallback
- docs: add the Menubarn mascot to the README
- Advertise the menu-bar suite
- feat: yield the status item during a curtain peek
- Run the pmset/ioreg poll off the main thread so it can't freeze the menu
- docs: document Start at Login options in the README
- fix: battery glyph uses opaque adaptive ink (not translucent labelColor)
- fix: battery glyph adapts to the menu-bar appearance
- docs: note the standalone Swift app
- feat: instant plug/unplug via IOKit power-source notifications
- feat: BatteryTime app (status glyph, full dropdown, polling)
- feat: battery glyph image (ported from render-title.swift)
- feat: 24h usage parse + battery tips triggers
- feat: battery math (health, humanize, temp, ETA stopgap)
- feat: ioreg AppleSmartBattery parsing
- feat: package skeleton + pmset -g batt parsing
- docs: add Swift app implementation plan
- docs: add menu-bar glyph states (charging/high-power/low-power/low/normal) to README
- feat: High Power = blue fill (incl. while charging), drop 💪
- feat: native-style battery glyph with %-left, 💪 High Power, fixed charging bolt
- feat: show 95% of macOS's remaining estimate
- change: cap only our stop-gap estimate, show macOS's estimate as-is
- feat: cap on-battery estimate at nominal; render whole hours as "Nh"
- feat: nominal time estimate on unplug when discharge draw is 0
- fix: battery glyph by default, bolt only while charging
- revert: menu bar back to bolt + time (drop the battery glyph)
- feat: show an instant time estimate on unplug before macOS computes one
- feat: visible charging bolt (outline halo) + circular Energy Mode icons
- feat: icon/%/time display toggles + native "Energy Mode" dropdown header
- feat: native-style battery icon in the menu bar
- feat: collapse battery tips to a "Battery Life Tips" item with a popup
- feat: behavior-based battery-longevity tips in the dropdown
- feat: 24-hour on-battery vs plugged usage in the dropdown
- feat: °C/°F temperature unit toggle in the dropdown
- feat: battery health, power draw, adapter & temp/voltage/charge in dropdown
- feat: 3-mode energy selector, hidden defaults, tight image-rendered title
- feat: bolt/ETA menu bar, details dropdown, instant plug/unplug updates
- feat: battery time-remaining menu-bar SwiftBar plugin
