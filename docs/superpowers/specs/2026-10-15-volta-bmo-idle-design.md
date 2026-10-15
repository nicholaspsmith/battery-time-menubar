# Volta: a BMO face that idles

Date: 2026-10-15. Status: approved; amended 2026-10-15 (gestures only).

> **Amendment, 2026-10-15:** every status-item image update costs macOS about
> 5 ms of CPU, whatever the image (measured), so a continuous 4 fps breath
> can't meet the energy budget. Nick chose **gestures only**: there's no
> continuous breath, an occasional slow sigh lifts the face instead, and
> nothing is drawn between gestures. The numbers below are the amended ones.

## Goal

Give Volta (Battery Time's menu-bar mascot) a face like BMO's from Adventure
Time, so it reads as a digital face, and keep him moving all the time like
parity's Polly. He glances back and forth, breathes, blinks and yawns. Every
state idles in its own way: on battery, charging and full.

Agreed with Nick:
- Face style "A, smooth BMO", from the mockup sheet: smooth vector shapes in
  BMO's proportions, not pixel art and not a dot-matrix grid.
- An idle in every state, each with its own character.
- Approach 1, a procedural idle: a seeded, unit-tested `IdleDriver` turns time
  into a handful of numbers, and `BatteryGlyph` draws them, the same way the
  sip and slosh animations already work.

Kept from 1.10.0, restyled to the new face:
- the charge-driven mouth;
- the ^ ^ eyes while drinking and the ‿ ‿ eyes when full;
- the twice-a-minute cue (slosh and blink on battery, burp when full);
- the sip loop;
- every aging stage, wrinkles to fallen terminal.

## 1. The face

All features are still knocked out of the fill and inked over the empty part,
split along the fill's edge exactly as today. Sizes are in points at the face
size (`bodyH` 17).

- **Eyes:** solid dots 2.4 wide by 2.6 tall. Their centres sit 6.5 either side
  of the body's centre (5.8 today) and 1.9 above it.
- **Mouth:** a wide, shallow curve 8 across (5.8 today), drawn with a 1.1 line,
  its ends 1.8 below centre. Its depth follows the charge:
  - a smile 1.8 deep at 60% charge and above;
  - flat from 35%;
  - a frown 0.9 deep below 35%, and whenever the fill is red.
- **The cue's grin** (the slosh) becomes BMO's open D: a filled half disc 7
  wide and 3.2 deep.
- **Drinking:** the ^ ^ eyes, re-spaced to the new eye positions. The pursed
  lips round the straw and the straw itself are unchanged.
- **Full:** the ‿ ‿ eyes, re-spaced. The small closed mouth and the burp are
  unchanged.
- **Aging:** every 1.10.0 aging feature is placed from the new eye and mouth
  geometry. Brows, bags, crow's feet and forehead creases follow the eyes, and
  laugh lines sit just outside the mouth's ends. Heavy lids cut the tops off
  the dots, and the ✕ eye replaces the right dot. The crack, band-aid, drips,
  puddle and terminal belong to the casing, so the idle never moves them.

### What the idle moves

`BatteryGlyph.image` gains one parameter, `idle: BatteryGlyph.Idle = .still`.
`BatteryGlyph.Idle` is a small struct defined in `BatteryGlyph.swift`, because
that file must keep compiling on its own: the Menumon site's `render-glyphs.sh`
builds it alone. Its fields, all `CGFloat`:

| Field | Range | Drawn as |
|---|---|---|
| `gaze` | −1…1 | Every face feature (eyes, mouth, aging lines) shifts 2pt per unit horizontally. |
| `breath` | 0…1 | A sigh. Every face feature rises by `breath × 0.6pt` (0.8pt when full). |
| `blink` | 0…1 | Merges with the cue's blink (the larger wins): the dots squash, and become a line above 0.85. |
| `yawn` | 0…1 | The mouth becomes an open oval 3.6 wide and up to 4.2 tall, eyes shut with it (blink at least `yawn`). On battery and when full only. |
| `doze` | 0…1 | Full only. 1 is the ‿ ‿ eyes. Below 1 the eyes open to dots, squashed by `doze`, and switch to ‿ ‿ above 0.85. |
| `peek` | 0…1 | Charging only. 0 is the ^ ^ eyes. Above 0 they open to dots, squashed by `1 − peek`, and become ^ ^ again below 0.15. |
| `tired` | 0…1 | Lids drooping by a third at 1. Combines with the aging lids (the larger droop wins). |

`.still` is all zeros, except `doze`, which is 1, so a still glyph looks
exactly as it does today in every state.

## 2. Idle behaviours: `IdleDriver`

`Sources/BatteryTimeCore/IdleDriver.swift`, Foundation only, fully unit-tested.

```swift
public enum IdleMood: Equatable { case awake(tired: Bool), drinking, sleepy }

public struct IdlePose: Equatable {
    public var gaze, breath, blink, yawn, doze, peek, tired: Double
    /// A mood's pose between gestures: all 0, except `doze` 1 when sleepy
    /// and `tired` 1 when awake and tired.
    public static func resting(_ mood: IdleMood) -> IdlePose
}

public struct IdleDriver {
    public init(seed: UInt64, mood: IdleMood, at t: TimeInterval)
    public mutating func setMood(_ mood: IdleMood, at t: TimeInterval)
    public mutating func setCue(playing: Bool, at t: TimeInterval)
    public mutating func pose(at t: TimeInterval) -> IdlePose
    /// Seconds from `t` until the pose next needs drawing.
    public mutating func nextTick(after t: TimeInterval) -> TimeInterval
}
```

Time is any monotonic clock in seconds (the app uses `ProcessInfo.systemUptime`).
Gestures come from a seeded generator (SplitMix64), so a test can replay a
timeline exactly. Each gesture is scheduled when the previous one of its kind
ends, at a uniformly random interval from the ranges below.

**Awake** (on battery):
- **Glance:** every 10–20 s, left or right at random. It eases over in 0.25 s,
  holds for 1–2.5 s, then eases back in 0.25 s. Gaze reaches ±1.
- **Blink:** every 5–9 s. It takes 0.18 s (close 0.06, hold 0.04, open 0.08).
  A quarter of blinks are doubled, the second 0.25 s after the first.
- **Yawn:** every 120–240 s, or every 45–90 s when tired. It takes 2.6 s: open
  0.6, hold 1.2, close 0.8.
- **Sigh:** every 40–70 s, 3 s long: breathe in over 40%, hold 10%, breathe
  out over 50%.
- **Tired** (`awake(tired: true)`, which the app sets at 20% charge and below):
  `tired` is 1, plus the faster yawns.

**Drinking** (charging):
- **Peek:** every 10–20 s. It takes 1.6 s: eyes open over 0.15 s, gaze to ±1
  and back over 1.3 s, eyes close over 0.15 s.
- No blinks, since his eyes are already closed. No yawns.
- **Sigh:** every 20–40 s, 3 s long.

**Sleepy** (full):
- **Resting pose:** `doze` 1.
- **Stir:** every 40–80 s, 5.6 s in all:
  - wake (`doze` 1 → 0 over 0.4 s);
  - a glance one way, 1.2 s;
  - a yawn, 2.6 s;
  - doze off (`doze` 0 → 1 over 0.8 s), then a 0.6 s settle.
- **Sigh:** every 15–30 s, 4 s long (deeper).

**Rules:**
- A yawn never overlaps a glance or a blink. A gesture due during a yawn waits
  for it to end, and a yawn due during another gesture waits for that one.
- **Cue:** while `setCue(playing: true)` holds, no gesture starts, and `gaze`,
  `peek` and `yawn` ease to 0 over 0.2 s. `blink` stays 0, because the cue
  draws its own blink. Gestures resume when the cue ends.
- **Mood change:** every field eases to the new mood's resting pose over
  0.3 s, and the new mood's schedule starts from that moment. Its first
  gesture is drawn from its own interval, so nothing fires instantly.
- **Easing:** smoothstep on every ramp.

**`nextTick`:**
- 1/10 s while any ramp is in progress (a glance or peek easing, a blink, a
  yawn, a stir, a mood or cue ease);
- 1/4 s while only a sigh moves;
- otherwise one frame into the next gesture (a gesture's first instant looks
  like rest), and never more than 60 s.

## 3. Wiring in the app

`main.swift`:

- **One animation clock** replaces `sipTimer`. It's a one-shot `Timer` that each
  tick re-arms itself for `min(driver.nextTick, sip need)` with a 10%
  tolerance. The sip need is 1/12 s while drinking, so the sip loop keeps its
  current timing. Each tick redraws.
- **When the clock runs:** the icon and face are both shown, Reduce Motion is
  off, the display is awake and the session is active. It stops on
  `NSWorkspace.screensDidSleepNotification` and
  `sessionDidResignActiveNotification`, and restarts on their wake and active
  counterparts. When it stops it shows the still glyph.
- **Mood:**
  - charging → `.drinking`;
  - plugged in and not charging → `.sleepy`;
  - otherwise `.awake(tired: pct <= 20)`.

  It is set on every render, and the driver ignores repeats.
- **Cue:** the minute animation's start and completion call
  `driver.setCue(playing:at:)`.
- **Settings ▸ Animate Volta:** a `ToggleMenuItem` after the four "Menu bar
  shows…" toggles, behind a separator. It's backed by `DisplayPrefs.animateFace`
  (key `animateFace`, default true). Off means `idle` is `.still`, and the clock
  runs only for the sip loop, exactly as in 1.10.0. The cue is unaffected.
  Reduce Motion stills everything, as today.
- **Seed:** a random seed at launch.

## 4. Energy budget

On battery, the idle adds about 0.5% of one core. Each redraw costs macOS
about 5 ms whatever the image, so that means about one redraw a second. The
driver averages 1.13 updates/s on battery (measured over 5 seeds × 1 h). On
the device that measured as about 0.7% of a core added (idle on 2.8% vs off
2.1%, the rest being the app's existing polling), which was reported to Nick.

## 5. Testing

- **`IdleDriverTests`** (TDD, `Tests/BatteryTimeCoreTests`):
  - The same seed gives identical poses at sampled times.
  - The pose is the mood's resting pose at start, and the new mood's resting
    pose 0.3 s after a mood change (barring a gesture).
  - Every glance returns `gaze` to 0.
  - While awake, every 6 s window contains a blink.
  - A yawn never overlaps a nonzero `gaze` or `blink`.
  - Tired yawns come more often than untired ones over a long run.
  - Sleepy has `doze` at 1 for most of a long run.
  - The cue drives `gaze` to 0 within 0.25 s and starts no gesture.
  - `nextTick` is 1/15 s mid-ramp, 1/4 s at rest, and never past the next
    gesture.
- **The existing age and core tests** stay green.
- **Visual:**
  - A sheet of every state × idle pose (gaze ±1, blink, yawn, doze, peek,
    tired) × aging stage at 2× and 5×, in dark and light.
  - An animated preview of about 20 s of each state's idle, reviewed by Nick
    before anything ships.
- **Energy:**
  - Time `BatteryGlyph.image` over many frames and multiply by the frame rates.
  - Sample the running app's CPU (`top -pid`) with the idle on and off, in
    whatever power state the Mac is in, and report which states were measured.

## 6. Release

- Branch `volta-idle`, version **1.11.0**.
- CHANGELOG entry.
- README: the face, the idle per state, the Animate Volta setting, and Reduce
  Motion.
- New README images from `render-glyphs.sh`. Restore any unrelated repos it
  touches.
- Nick reviews the images and preview before the push. The site's cards
  showing the idle loop is a separate follow-up.

## Out of scope

- Pixel-art or dot-matrix faces.
- Idle loops on the Menumon site's cards and hero bar.
- Any change to the aging thresholds, the leak colours or the straw.
