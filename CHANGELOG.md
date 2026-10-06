# Changelog

Every push to `main` is a release. Before pushing, add a `## [X.Y.Z] - YYYY-MM-DD`
section at the top with `- ` entries (minor for features, patch for fixes); if an
`## [Unreleased]` section is waiting, turn it into that section. GitHub tags it
and publishes the section as the release notes; a push or pull request
without one is refused (`[no release]` in the tip commit is the only exception).
Versions follow [Semantic Versioning](https://semver.org/). The full rule:
[StatusItemKit — Releases](https://github.com/nicholaspsmith/StatusItemKit#releases-every-push-is-one).

## [1.6.1] - 2026-10-05

- New app icon: Volta as he looks in the menu bar

## [1.6.0] - 2026-10-05

- While charging, Volta drinks through a red bendy straw from a big cup in front of him: the charge climbs the straw, stays full for a few seconds while he gulps, then drains back for the next sip
- His burp no longer shows little cheeks either side of his mouth

## [1.5.0] - 2026-10-05

- feat: a Settings submenu holds Menu bar shows… (icon, face, percentage, time remaining) and the °C/°F switch, along with Start at Login and the version
- Quit now reads "Quit Battery Time"

## [1.4.0] - 2026-10-05

- While charging, bubbles run up Volta's straw into his mouth and his charge ripples and bubbles as it fills
- Volta's straw no longer has an outline
- feat: Volta ages with the battery: wrinkles deepen as health falls from 100% to 80%, and from 80% down he is a grandpa
- Health shows in the menu again on Macs whose battery no longer reports the old capacity keys

## [1.3.0] - 2026-10-05

- New app icon: Volta as he looks in the menu bar, a horizontal battery with round eyes and a smile
- Volta's straw has candy stripes right across it and only a gentle bend up to his mouth

## [1.2.2] - 2026-10-05

- Full and plugged in, Volta has no cheeks; they appear only while he burps

## [1.2.1] - 2026-10-05

- Volta's straw comes up from below the battery and into his mouth from the side
- Full and plugged in, he has small cheeks rather than big puffed ones

## [1.2.0] - 2026-10-05

- Charging, Volta (the battery face) drinks through a straw, a bead of charge running down it every couple of seconds
- Plugged in but not charging, he is stuffed — eyes closed, cheeks puffed, glowing yellow — instead of turning into a plug
- Once a minute he blinks while his charge sloshes from side to side, or burps when stuffed, taking his turn with the other Menumon mascots. Skipped under Reduce Motion

## [1.1.1] - 2026-09-28

- `install.sh` now installs the app: it builds Battery Time.app, links it into ~/Applications, asks whether to turn on Start at Login (skipped when it is already on, or when there is no terminal to ask in), and relaunches it. It also removes the retired SwiftBar plugin link and its power-watch launchd agent, which the app replaces. `./install.sh --swiftbar` still installs the plugin instead

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
