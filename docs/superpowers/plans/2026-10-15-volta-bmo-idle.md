# Volta's BMO Face and Idle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Volta a smooth, BMO-proportioned digital face and a constant,
varied idle (glances, breaths, blinks, yawns, peeks, dozing) in every state.

**Architecture:**
- A pure, seeded `IdleDriver` in `BatteryTimeCore` turns time and mood into an
  `IdlePose`, and tells the app when the pose next needs drawing.
- `BatteryGlyph` draws a matching `BatteryGlyph.Idle`, and gets the BMO
  restyle.
- `main.swift` runs one self-rescheduling timer for the idle and the sip loop.
  The timer stops whenever Volta can't or shouldn't move.

**Tech Stack:** Swift 5.9 SwiftPM, AppKit, XCTest, StatusItemKit (sibling
checkout `../StatusItemKit`).

**Spec:** `docs/superpowers/specs/2026-10-15-volta-bmo-idle-design.md`. Read
it before starting. This plan argues from it.

## Global Constraints

- macOS 13 or later (`platforms: [.macOS(.v13)]`), swift-tools-version 5.9.
- `Sources/BatteryTime/BatteryGlyph.swift` must compile on its own with only
  `import AppKit`: no `BatteryTimeCore` types. The Menumon site's
  `render-glyphs.sh` builds it alone.
- Every push to `main` is a release. The PR's tip commit needs a new
  `## [X.Y.Z] - YYYY-MM-DD` CHANGELOG section. Never tag by hand, never
  `gh pr merge --admin`, and merge with plain `gh pr merge --merge` once
  `release / check` passes. This release is **1.11.0**.
- Push over SSH (the remote is already `git@github.com:…`).
- Nick reviews the images and the animated preview **before** anything is
  pushed, and approves the site deploy separately.
- Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Intermediate
  commits on the branch use `[no release]` in their message. The final
  release commit doesn't.
- Every number in the spec is copied verbatim below. If the spec and this plan
  ever disagree, the spec wins.

## Review Focus

1. **A clock gap (the display slept, or the timer was off for an hour).** The
   pose must not replay missed gestures, and gestures shouldn't burst on wake.
   Pinned by `testWakingFromALongPauseReplaysNothing` (Task 1).
2. **Rapid plug and unplug (mood flapping).** Every field stays in range and
   ticks stay between 1/60 s and 60 s (1/4 s before the gestures-only
   amendment). Pinned by
   `testMoodFlappingStaysInRange` (Task 1).
3. **Charge crossing 20% on battery.** The lids ease down over 0.3 s instead of
   snapping. Pinned by `testTiredLidsEaseIn` (Task 1).
4. **Animate Volta off, or Reduce Motion on, while charging.** The sip loop
   still runs when only the idle is off, and Reduce Motion stills everything.
   Pinned by `testSipLoopRunsWithoutTheIdle` and `testReduceMotionStillsHim`
   (Task 3).
5. **Face hidden, display asleep, or session inactive.** No timer at all.
   Pinned by `testNothingMovesWhenHeCantBeSeen` (Task 3).

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/BatteryTimeCore/IdleDriver.swift` (new) | `IdleMood`, `IdlePose`, `IdleDriver`, `SplitMix64`: the idle timeline. |
| `Sources/BatteryTimeCore/VoltaMotion.swift` (new) | Small pure decisions for the app: `idleMood`, `voltaMayMove`, `animationDelay`. |
| `Sources/BatteryTime/BatteryGlyph.swift` | BMO restyle, plus the `Idle` struct and its drawing. |
| `Sources/BatteryTime/main.swift` | The animation clock, mood and cue hooks, sleep and session pauses, the Settings toggle. |
| `Sources/BatteryTime/DisplayPrefs.swift` | `animateFace` pref. |
| `Tests/BatteryTimeCoreTests/IdleDriverTests.swift` (new) | Driver behaviour. |
| `Tests/BatteryTimeCoreTests/VoltaMotionTests.swift` (new) | App decisions. |
| `Tests/BatteryTimeTests/Raster.swift` (new) | Test helper: rasterise a glyph and measure its ink. |
| `Tests/BatteryTimeTests/GlyphFaceTests.swift` (new) | Face geometry and idle drawing. |
| `Tests/BatteryTimeTests/GlyphPerformanceTests.swift` (new) | Per-frame cost. |
| `README.md`, `CHANGELOG.md`, `screenshots/*.png`, `docs/*.png` | Release docs and images. |

---

### Task 1: `IdleDriver`

**Files:**
- Create: `Sources/BatteryTimeCore/IdleDriver.swift`
- Test: `Tests/BatteryTimeCoreTests/IdleDriverTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (used by Tasks 3 and 4):
  - `public enum IdleMood: Equatable { case awake(tired: Bool), drinking, sleepy }`
  - `public struct IdlePose: Equatable { var gaze, breath, blink, yawn, doze, peek, tired: Double }`,
    with `init(gaze:breath:blink:yawn:doze:peek:tired:)` (all defaulting to 0)
    and `static func resting(_: IdleMood) -> IdlePose`.
  - `public struct IdleDriver`:
    - `init(seed: UInt64, mood: IdleMood, at: TimeInterval)`
    - `mutating func setMood(_: IdleMood, at: TimeInterval)`
    - `mutating func setCue(playing: Bool, at: TimeInterval)`
    - `mutating func pose(at: TimeInterval) -> IdlePose`
    - `mutating func nextTick(after: TimeInterval) -> TimeInterval`
    - `static let movingTick = 1.0/15`, `static let restingTick = 1.0/4`, `static let minimumTick = 1.0/60`

- [ ] **Step 1: Write the failing tests**

Create `Tests/BatteryTimeCoreTests/IdleDriverTests.swift`:

```swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BatteryTimeCore

final class IdleDriverTests: XCTestCase {
    /// Samples `field` every `dt` from `from` to `to`, and returns the spans
    /// where it is nonzero (start, end), merging gaps shorter than `merge`.
    private func episodes(_ d: inout IdleDriver, from: Double, to: Double, dt: Double = 0.01,
                          merge: Double = 0.2, _ field: (IdlePose) -> Double) -> [(Double, Double)] {
        var spans: [(Double, Double)] = []
        var t = from
        while t <= to {
            if abs(field(d.pose(at: t))) > 1e-12 {
                if let last = spans.last, t - last.1 <= merge { spans[spans.count - 1].1 = t }
                else { spans.append((t, t)) }
            }
            t += dt
        }
        return spans
    }

    func testSameSeedSamePoses() {
        var a = IdleDriver(seed: 7, mood: .awake(tired: false), at: 0)
        var b = IdleDriver(seed: 7, mood: .awake(tired: false), at: 0)
        var c = IdleDriver(seed: 8, mood: .awake(tired: false), at: 0)
        var differs = false
        for i in 0...2400 {
            let t = Double(i) * 0.05
            let pa = a.pose(at: t)
            XCTAssertEqual(pa, b.pose(at: t))
            if pa != c.pose(at: t) { differs = true }
        }
        XCTAssertTrue(differs, "a different seed should give a different timeline")
    }

    func testStartsAtItsMoodsRestingPose() {
        for mood in [IdleMood.awake(tired: false), .awake(tired: true), .drinking, .sleepy] {
            var d = IdleDriver(seed: 1, mood: mood, at: 5)
            XCTAssertEqual(d.pose(at: 5), .resting(mood), "\(mood)")
        }
    }

    func testMoodChangeEasesToTheNewRestingPose() {
        var d = IdleDriver(seed: 3, mood: .awake(tired: false), at: 0)
        _ = d.pose(at: 49.9)
        d.setMood(.sleepy, at: 50)
        let mid = d.pose(at: 50.15)
        XCTAssertGreaterThan(mid.doze, 0); XCTAssertLessThan(mid.doze, 1)
        let after = d.pose(at: 50.31)
        XCTAssertEqual(after.doze, 1); XCTAssertEqual(after.gaze, 0)
        XCTAssertEqual(after.blink, 0); XCTAssertEqual(after.yawn, 0)
    }

    func testTiredLidsEaseIn() {
        var d = IdleDriver(seed: 4, mood: .awake(tired: false), at: 0)
        _ = d.pose(at: 9.9)
        d.setMood(.awake(tired: true), at: 10)
        let mid = d.pose(at: 10.15).tired
        XCTAssertGreaterThan(mid, 0); XCTAssertLessThan(mid, 1)
        XCTAssertEqual(d.pose(at: 10.31).tired, 1)
    }

    func testEveryGlanceComesBackToCentre() {
        var d = IdleDriver(seed: 11, mood: .awake(tired: false), at: 0)
        let glances = episodes(&d, from: 0, to: 300) { $0.gaze }
        XCTAssertGreaterThan(glances.count, 20)
        for (start, end) in glances { XCTAssertLessThanOrEqual(end - start, 3.0 + 0.02) }
    }

    func testBlinksComeEveryThreeToSixSecondsUnlessAYawnHoldsThemBack() {
        var d = IdleDriver(seed: 12, mood: .awake(tired: false), at: 0)
        let blinks = episodes(&d, from: 0, to: 300, dt: 0.005) { $0.blink }
        XCTAssertGreaterThan(blinks.count, 40)
        for (a, b) in zip(blinks, blinks.dropFirst()) {
            let gap = b.0 - a.1
            XCTAssertGreaterThanOrEqual(gap, 2.9)
            XCTAssertLessThanOrEqual(gap, 6.0 + 2.6 + 0.1)   // a yawn (2.6 s) can hold a blink back
        }
    }

    func testAYawnNeverOverlapsAGlanceOrABlink() {
        var d = IdleDriver(seed: 13, mood: .awake(tired: true), at: 0)
        var yawns = 0.0
        var t = 0.0
        while t < 900 {
            let p = d.pose(at: t)
            if p.yawn > 0 { yawns += 1; XCTAssertEqual(p.gaze, 0, "t=\(t)"); XCTAssertEqual(p.blink, 0, "t=\(t)") }
            t += 0.01
        }
        XCTAssertGreaterThan(yawns, 0)
    }

    func testTiredYawnsComeMoreOften() {
        var tired = IdleDriver(seed: 14, mood: .awake(tired: true), at: 0)
        var fresh = IdleDriver(seed: 14, mood: .awake(tired: false), at: 0)
        let t = episodes(&tired, from: 0, to: 3600, dt: 0.05) { $0.yawn }.count
        let f = episodes(&fresh, from: 0, to: 3600, dt: 0.05) { $0.yawn }.count
        XCTAssertGreaterThanOrEqual(t, 35)
        XCTAssertLessThanOrEqual(f, 30)
    }

    func testSleepyMostlyDozes() {
        var d = IdleDriver(seed: 15, mood: .sleepy, at: 0)
        var dozing = 0, total = 0
        var t = 0.0
        while t < 1800 { if d.pose(at: t).doze == 1 { dozing += 1 }; total += 1; t += 0.05 }
        XCTAssertGreaterThanOrEqual(Double(dozing) / Double(total), 0.85)
        var again = IdleDriver(seed: 15, mood: .sleepy, at: 0)
        XCTAssertGreaterThan(episodes(&again, from: 0, to: 600, dt: 0.05) { $0.yawn }.count, 5, "he stirs and yawns")
    }

    func testDrinkingPeeksAndNeverBlinksOrYawns() {
        var d = IdleDriver(seed: 16, mood: .drinking, at: 0)
        var peeks = 0.0, t = 0.0
        while t < 300 {
            let p = d.pose(at: t)
            XCTAssertEqual(p.blink, 0); XCTAssertEqual(p.yawn, 0)
            if p.peek > 0 { peeks += 1 }
            t += 0.02
        }
        XCTAssertGreaterThan(peeks, 0)
    }

    func testTheCueCentresHisGazeAndStartsNothing() {
        var d = IdleDriver(seed: 17, mood: .awake(tired: false), at: 0)
        var t = 0.0
        while abs(d.pose(at: t).gaze) < 1 { t += 0.01; XCTAssertLessThan(t, 120, "no held glance found") }
        d.setCue(playing: true, at: t)
        XCTAssertEqual(d.pose(at: t + 0.25).gaze, 0)
        var u = t + 0.25
        while u < t + 20 {
            let p = d.pose(at: u)
            XCTAssertEqual(p.gaze, 0); XCTAssertEqual(p.blink, 0); XCTAssertEqual(p.yawn, 0)
            u += 0.05
        }
        d.setCue(playing: false, at: t + 20)
        XCTAssertFalse(episodes(&d, from: t + 20, to: t + 30) { $0.blink }.isEmpty, "gestures resume")
    }

    func testNextTickRestsBetweenGestures() {
        var d = IdleDriver(seed: 18, mood: .awake(tired: false), at: 0)
        _ = d.pose(at: 0.5)
        XCTAssertEqual(d.nextTick(after: 0.5), IdleDriver.restingTick)   // first blink is 3 s or more away
    }

    func testNextTickHurriesMidGestureAndThroughAMoodChange() {
        var d = IdleDriver(seed: 19, mood: .awake(tired: false), at: 0)
        var t = 0.0
        while d.pose(at: t).blink == 0 { t += 0.005 }
        XCTAssertEqual(d.nextTick(after: t), IdleDriver.movingTick)
        d.setMood(.drinking, at: t + 1)
        XCTAssertEqual(d.nextTick(after: t + 1.1), IdleDriver.movingTick)
    }

    func testTickDrivenDrawingNeverMissesAGesture() {
        var dense = IdleDriver(seed: 20, mood: .awake(tired: false), at: 0)
        var ticked = IdleDriver(seed: 20, mood: .awake(tired: false), at: 0)
        let denseBlinks = episodes(&dense, from: 0, to: 600, dt: 0.005) { $0.blink }.count
        var dense2 = IdleDriver(seed: 20, mood: .awake(tired: false), at: 0)
        let denseGlances = episodes(&dense2, from: 0, to: 600, dt: 0.005) { $0.gaze }.count
        var blinks: [(Double, Double)] = [], glances: [(Double, Double)] = []
        var t = 0.0
        while t <= 600 {
            let p = ticked.pose(at: t)
            for (value, list) in [(p.blink, 0), (p.gaze, 1)] where abs(value) > 1e-12 {
                if list == 0 { if let l = blinks.last, t - l.1 <= 0.2 { blinks[blinks.count - 1].1 = t } else { blinks.append((t, t)) } }
                else { if let l = glances.last, t - l.1 <= 0.2 { glances[glances.count - 1].1 = t } else { glances.append((t, t)) } }
            }
            let step = ticked.nextTick(after: t)
            XCTAssertGreaterThanOrEqual(step, IdleDriver.minimumTick)
            XCTAssertLessThanOrEqual(step, IdleDriver.restingTick)
            t += step
        }
        XCTAssertEqual(blinks.count, denseBlinks)
        XCTAssertEqual(glances.count, denseGlances)
    }

    func testWakingFromALongPauseReplaysNothing() {
        var d = IdleDriver(seed: 21, mood: .awake(tired: false), at: 0)
        var t = 0.0
        while t < 100 { _ = d.pose(at: t); t += 0.05 }
        let woke = d.pose(at: 3700)
        XCTAssertEqual(woke.gaze, 0); XCTAssertEqual(woke.blink, 0); XCTAssertEqual(woke.yawn, 0)
        XCTAssertLessThanOrEqual(episodes(&d, from: 3700, to: 3710, dt: 0.005) { $0.blink }.count, 3)
    }

    func testMoodFlappingStaysInRange() {
        var d = IdleDriver(seed: 22, mood: .awake(tired: false), at: 0)
        var t = 0.0
        var flip = false
        while t < 10 {
            if Int(t * 1000) % 100 == 0 { flip.toggle(); d.setMood(flip ? .drinking : .awake(tired: false), at: t) }
            let p = d.pose(at: t)
            for v in [p.gaze, p.breath] { XCTAssertGreaterThanOrEqual(v, -1); XCTAssertLessThanOrEqual(v, 1) }
            for v in [p.blink, p.yawn, p.doze, p.peek, p.tired] { XCTAssertGreaterThanOrEqual(v, 0); XCTAssertLessThanOrEqual(v, 1) }
            let n = d.nextTick(after: t)
            XCTAssertGreaterThanOrEqual(n, IdleDriver.minimumTick); XCTAssertLessThanOrEqual(n, IdleDriver.restingTick)
            t += 0.01
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter IdleDriverTests 2>&1 | grep -E "error:|Executed" | head`
Expected: the build fails with `cannot find 'IdleDriver' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/BatteryTimeCore/IdleDriver.swift`:

```swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Volta's mood, which picks what his idle does.
public enum IdleMood: Equatable {
    /// On battery. Tired at low charge: heavy lids and more yawns.
    case awake(tired: Bool)
    /// Charging, sipping through his straw.
    case drinking
    /// Full: dozing.
    case sleepy
}

/// Where Volta's idle has him at one moment: what `BatteryGlyph.Idle` draws.
public struct IdlePose: Equatable {
    /// −1…1: his face turned left…right.
    public var gaze: Double
    /// −1…1: the rise and fall of a breath.
    public var breath: Double
    /// 0…1: eyes open…shut.
    public var blink: Double
    /// 0…1: mouth closed…yawning wide.
    public var yawn: Double
    /// 0…1: awake…dozing (full only).
    public var doze: Double
    /// 0…1: drinking eyes ^ ^…peeking dots (charging only).
    public var peek: Double
    /// 0…1: lids up…drooping (tired).
    public var tired: Double

    public init(gaze: Double = 0, breath: Double = 0, blink: Double = 0, yawn: Double = 0,
                doze: Double = 0, peek: Double = 0, tired: Double = 0) {
        self.gaze = gaze; self.breath = breath; self.blink = blink; self.yawn = yawn
        self.doze = doze; self.peek = peek; self.tired = tired
    }

    /// A mood's pose between gestures: all 0, except `doze` 1 when sleepy
    /// and `tired` 1 when awake and tired.
    public static func resting(_ mood: IdleMood) -> IdlePose {
        switch mood {
        case .awake(let tired): return IdlePose(tired: tired ? 1 : 0)
        case .drinking: return IdlePose()
        case .sleepy: return IdlePose(doze: 1)
        }
    }

    /// `a` blended toward `b` by `f` (0…1).
    static func mix(_ a: IdlePose, _ b: IdlePose, _ f: Double) -> IdlePose {
        func m(_ x: Double, _ y: Double) -> Double { x + (y - x) * f }
        return IdlePose(gaze: m(a.gaze, b.gaze), breath: m(a.breath, b.breath), blink: m(a.blink, b.blink),
                        yawn: m(a.yawn, b.yawn), doze: m(a.doze, b.doze), peek: m(a.peek, b.peek),
                        tired: m(a.tired, b.tired))
    }
}

/// Volta's idle: glances, blinks, yawns, peeks, stirs and breaths on a
/// seeded random timeline, so it varies but a test can replay it exactly.
/// Time is any monotonic clock in seconds. Each gesture is scheduled when
/// the previous one of its kind ends, at a random interval for its kind.
public struct IdleDriver {
    /// Redraw intervals: while something moves, while he only breathes, and
    /// the shortest the menu bar is ever asked for.
    public static let movingTick: TimeInterval = 1.0 / 15
    public static let restingTick: TimeInterval = 1.0 / 4
    public static let minimumTick: TimeInterval = 1.0 / 60

    static let moodEase: TimeInterval = 0.3
    static let cueEase: TimeInterval = 0.2

    enum Kind: CaseIterable { case glance, blink, yawn, peek, stir }

    struct Gesture {
        let kind: Kind
        let start: TimeInterval
        let length: TimeInterval
        /// −1 or 1: which way a glance (or a peek's or stir's glance) looks.
        let side: Double
        /// How long a glance holds (glance only).
        let hold: TimeInterval
        /// A second blink 0.25 s after the first (blink only).
        let double: Bool
        var end: TimeInterval { start + length }
    }

    private var rng: SplitMix64
    private var mood: IdleMood
    private var next: [Kind: TimeInterval] = [:]
    private var active: [Gesture] = []
    private var breathStart: TimeInterval
    private var cuePlaying = false
    private var cueChanged = -TimeInterval.infinity
    private var moodChanged = -TimeInterval.infinity
    private var moodFrom = IdlePose()
    private var last: TimeInterval

    public init(seed: UInt64, mood: IdleMood, at t: TimeInterval) {
        rng = SplitMix64(seed: seed)
        self.mood = mood
        breathStart = t
        last = t
        schedule(from: t)
    }

    /// A new mood eases in over 0.3 s from wherever he was, and its own
    /// schedule starts now. Repeats are ignored.
    public mutating func setMood(_ mood: IdleMood, at t: TimeInterval) {
        guard mood != self.mood else { return }
        moodFrom = pose(at: t)
        self.mood = mood
        moodChanged = t
        active.removeAll()
        schedule(from: t)
    }

    /// The minute cue: while it plays no gesture starts, and gaze, peek,
    /// yawn and blink ease to 0 over 0.2 s (the cue draws its own blink).
    public mutating func setCue(playing: Bool, at t: TimeInterval) {
        guard playing != cuePlaying else { return }
        advance(to: t)
        cuePlaying = playing
        cueChanged = t
    }

    public mutating func pose(at t: TimeInterval) -> IdlePose {
        advance(to: t)
        var p = IdlePose.resting(mood)
        p.breath = sin(2 * .pi * (t - breathStart) / (mood == .sleepy ? 6 : 4))
        for g in active where g.start <= t && t < g.end { apply(g, at: t - g.start, to: &p) }
        let c = cueMask(at: t)
        if c > 0 { p.gaze *= 1 - c; p.peek *= 1 - c; p.yawn *= 1 - c; p.blink *= 1 - c }
        let m = t - moodChanged
        if m < Self.moodEase { p = .mix(moodFrom, p, Self.ease(m / Self.moodEase)) }
        return p
    }

    /// Seconds from `t` until the pose next needs drawing: `movingTick` while
    /// anything ramps, else `restingTick`, never past the next gesture's start.
    public mutating func nextTick(after t: TimeInterval) -> TimeInterval {
        advance(to: t)
        if t - moodChanged < Self.moodEase || t - cueChanged < Self.cueEase { return Self.movingTick }
        var wait = Self.restingTick
        for g in active where g.start <= t && t < g.end {
            guard let still = stillUntil(g, at: t - g.start) else { return Self.movingTick }
            wait = min(wait, still - t)
        }
        if !cuePlaying {
            for k in Self.kinds(for: mood) { if let n = next[k] { wait = min(wait, n - t) } }
        }
        return max(wait, Self.minimumTick)
    }

    // MARK: Timeline

    private static func kinds(for mood: IdleMood) -> [Kind] {
        switch mood {
        case .awake: return [.glance, .blink, .yawn]
        case .drinking: return [.peek]
        case .sleepy: return [.stir]
        }
    }

    private mutating func schedule(from t: TimeInterval) {
        next = [:]
        for k in Self.kinds(for: mood) { next[k] = t + interval(k) }
    }

    private mutating func interval(_ k: Kind) -> TimeInterval {
        switch k {
        case .glance: return rng.uniform(6, 12)
        case .blink: return rng.uniform(3, 6)
        case .yawn: return mood == .awake(tired: true) ? rng.uniform(45, 90) : rng.uniform(120, 240)
        case .peek: return rng.uniform(10, 20)
        case .stir: return rng.uniform(40, 80)
        }
    }

    private mutating func gesture(_ k: Kind, at s: TimeInterval) -> Gesture {
        switch k {
        case .glance:
            let side: Double = rng.unit() < 0.5 ? -1 : 1
            let hold = rng.uniform(1, 2.5)
            return Gesture(kind: k, start: s, length: 0.25 + hold + 0.25, side: side, hold: hold, double: false)
        case .blink:
            let double = rng.unit() < 0.25
            return Gesture(kind: k, start: s, length: double ? 0.43 : 0.18, side: 0, hold: 0, double: double)
        case .yawn:
            return Gesture(kind: k, start: s, length: 2.6, side: 0, hold: 0, double: false)
        case .peek:
            return Gesture(kind: k, start: s, length: 1.6, side: rng.unit() < 0.5 ? -1 : 1, hold: 0, double: false)
        case .stir:
            return Gesture(kind: k, start: s, length: 5.6, side: rng.unit() < 0.5 ? -1 : 1, hold: 0, double: false)
        }
    }

    /// A yawn never shares the stage with a glance or a blink.
    private static func conflicts(_ a: Kind, _ b: Kind) -> Bool {
        (a == .yawn && (b == .glance || b == .blink)) || (b == .yawn && (a == .glance || a == .blink))
    }

    /// Starts every gesture due by `t`, in time order. A gesture due while a
    /// conflicting one plays waits for it to end.
    private mutating func advance(to t: TimeInterval) {
        let t = max(t, last)
        defer { last = t }
        // A clock that stopped (the display slept) doesn't replay what it
        // missed: anything that came due over a second ago starts afresh.
        for k in Kind.allCases { if let n = next[k], n < t - 1 { next[k] = t + interval(k) } }
        if !cuePlaying {
            while let due = earliestDue(by: t) {
                let (k, s) = due
                if let blocker = active.first(where: { $0.start <= s && s < $0.end && Self.conflicts($0.kind, k) }) {
                    next[k] = blocker.end
                    continue
                }
                let g = gesture(k, at: s)
                active.append(g)
                next[k] = g.end + interval(k)
            }
        }
        active.removeAll { $0.end <= t }
    }

    private func earliestDue(by t: TimeInterval) -> (Kind, TimeInterval)? {
        var best: (Kind, TimeInterval)?
        for k in Kind.allCases {
            guard let n = next[k], n <= t else { continue }
            if best == nil || n < best!.1 { best = (k, n) }
        }
        return best
    }

    // MARK: Shapes of the gestures

    private func apply(_ g: Gesture, at u: TimeInterval, to p: inout IdlePose) {
        switch g.kind {
        case .glance:
            p.gaze = g.side * Self.glance(u, hold: g.hold)
        case .blink:
            p.blink = max(Self.blink(u), g.double ? Self.blink(u - 0.25) : 0)
        case .yawn:
            p.yawn = Self.yawn(u)
        case .peek:
            // Eyes open over 0.15 s, a glance there and back over 1.3 s, closed over 0.15 s.
            p.peek = u < 0.15 ? Self.ease(u / 0.15) : u < 1.45 ? 1 : 1 - Self.ease((u - 1.45) / 0.15)
            p.gaze = g.side * Self.glance(u - 0.15, hold: 0.7, ramp: 0.3)
        case .stir:
            // Wake 0.4 s, glance 1.2 s, yawn 2.6 s, doze off 0.8 s, settle 0.6 s.
            p.doze = u < 0.4 ? 1 - Self.ease(u / 0.4) : u < 4.2 ? 0 : u < 5.0 ? Self.ease((u - 4.2) / 0.8) : 1
            p.gaze = g.side * Self.glance(u - 0.4, hold: 0.7, ramp: 0.25)
            p.yawn = Self.yawn(u - 1.6)
        }
    }

    /// While a glance holds still, when it moves again (absolute time).
    private func stillUntil(_ g: Gesture, at u: TimeInterval) -> TimeInterval? {
        guard g.kind == .glance, u >= 0.25, u < 0.25 + g.hold else { return nil }
        return g.start + 0.25 + g.hold
    }

    private func cueMask(at t: TimeInterval) -> Double {
        let e = Self.ease((t - cueChanged) / Self.cueEase)
        return cuePlaying ? e : 1 - e
    }

    static func glance(_ u: TimeInterval, hold: TimeInterval, ramp: TimeInterval = 0.25) -> Double {
        if u < 0 { return 0 }
        if u < ramp { return ease(u / ramp) }
        if u < ramp + hold { return 1 }
        if u < 2 * ramp + hold { return 1 - ease((u - ramp - hold) / ramp) }
        return 0
    }

    /// One blink: close 0.06 s, hold 0.04 s, open 0.08 s.
    static func blink(_ u: TimeInterval) -> Double {
        if u < 0 { return 0 }
        if u < 0.06 { return ease(u / 0.06) }
        if u < 0.10 { return 1 }
        if u < 0.18 { return 1 - ease((u - 0.10) / 0.08) }
        return 0
    }

    /// One yawn: open 0.6 s, hold 1.2 s, close 0.8 s.
    static func yawn(_ u: TimeInterval) -> Double {
        if u < 0 { return 0 }
        if u < 0.6 { return ease(u / 0.6) }
        if u < 1.8 { return 1 }
        if u < 2.6 { return 1 - ease((u - 1.8) / 0.8) }
        return 0
    }

    /// Smoothstep, clamped to 0…1.
    static func ease(_ u: Double) -> Double {
        guard u.isFinite else { return u > 0 ? 1 : 0 }
        let v = max(0, min(1, u)); return v * v * (3 - 2 * v)
    }
}

/// A small, fast, seedable generator (SplitMix64), so a timeline replays.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    mutating func uniform(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
}
```

Note on `cueMask`: `cueChanged` starts at −∞, so `(t − cueChanged) / cueEase`
is +∞, `ease` returns 1, and the mask is `1 − 1 = 0`. That's why `ease`
guards non-finite input.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter IdleDriverTests 2>&1 | grep -E "error:|failed|Executed" | head`
Expected: `Executed 16 tests, with 0 failures`.

- [ ] **Step 5: Run the whole suite**

Run: `swift test 2>&1 | grep -E "Suite 'All tests' (passed|failed)|with [1-9][0-9]* failures|error:"`
Expected: two `Suite 'All tests' passed` lines, and nothing else.

- [ ] **Step 6: Commit**

```bash
git add Sources/BatteryTimeCore/IdleDriver.swift Tests/BatteryTimeCoreTests/IdleDriverTests.swift
git commit -m "IdleDriver: Volta's seeded idle timeline [no release]

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The BMO face and drawing the idle

**Files:**
- Modify: `Sources/BatteryTime/BatteryGlyph.swift`. The `image(...)` signature
  is around line 38. The face block runs from `if face {` (around line 326)
  through the burp bubble just before `} else if charging {` (around line
  568).
- Create: `Tests/BatteryTimeTests/Raster.swift`,
  `Tests/BatteryTimeTests/GlyphFaceTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1. This file must not import `BatteryTimeCore`.
- Produces (used by Tasks 3 and 4):
  - `public struct BatteryGlyph.Idle`: `gaze`, `breath`, `blink`, `yawn`,
    `doze`, `peek`, `tired`, all `CGFloat`, with
    `init(gaze:breath:blink:yawn:doze:peek:tired:)` defaulting to 0, except
    `doze`, which defaults to 1.
  - `static let still`.
  - A new trailing parameter `idle: Idle = .still` on `BatteryGlyph.image(...)`.
  - Test helper `ink(_ img: NSImage, in rect: NSRect, scale: CGFloat = 4) -> Ink`,
    where `Ink` has `count`, `cx`, `cy`, `minX`, `maxX`, `minY` and `maxY`
    (all `Double`, in points).

- [ ] **Step 1: Write the test helper**

Create `Tests/BatteryTimeTests/Raster.swift`:

```swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit

/// The ink a rendered glyph puts inside a rect: alpha-weighted area (pt²),
/// centroid, and the extent of its solid (alpha > 0.5) pixels, in points with
/// y up.
struct Ink {
    var count = 0.0, cx = 0.0, cy = 0.0
    var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
}

func rasterize(_ img: NSImage, scale: CGFloat = 4) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(img.size.width * scale),
                               pixelsHigh: Int(img.size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = img.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(origin: .zero, size: img.size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func ink(_ img: NSImage, in rect: NSRect, scale: CGFloat = 4) -> Ink {
    let rep = rasterize(img, scale: scale)
    var r = Ink(), sx = 0.0, sy = 0.0
    let s = Double(scale), h = Double(img.size.height)
    for py in 0..<rep.pixelsHigh {
        for px in 0..<rep.pixelsWide {
            let x = (Double(px) + 0.5) / s, y = h - (Double(py) + 0.5) / s   // bitmap rows run top-down
            guard rect.contains(NSPoint(x: x, y: y)) else { continue }
            let a = Double(rep.colorAt(x: px, y: py)?.alphaComponent ?? 0)
            guard a > 0.02 else { continue }
            r.count += a / (s * s); sx += a * x; sy += a * y
            if a > 0.5 { r.minX = min(r.minX, x); r.maxX = max(r.maxX, x); r.minY = min(r.minY, y); r.maxY = max(r.maxY, y) }
        }
    }
    let w = r.count * s * s
    if w > 0 { r.cx = sx / w; r.cy = sy / w }
    return r
}
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/BatteryTimeTests/GlyphFaceTests.swift`. The geometry: with the
face on and no lead text, the body is 34 × 17pt at x = 0. On battery the image
is 17pt tall. Charging, full and dripping make it 22pt tall. The face's centre
is at x 17, y = image height / 2. The interior is 3.1pt in from each side.
Charge 0% leaves the fill empty, so the face is drawn in ink and can be
measured directly.

```swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
import AppKit
@testable import BatteryTime

final class GlyphFaceTests: XCTestCase {
    private let cx: CGFloat = 17

    private func volta(charging: Bool = false, plugged: Bool = false, age: CGFloat = 0,
                       idle: BatteryGlyph.Idle = .still) -> NSImage {
        BatteryGlyph.image(pct: 0, charging: charging, plugged: plugged, lead: "", trailing: "",
                           ink: .black, fill: .none, face: true, age: age, idle: idle)
    }
    private func cy(_ img: NSImage) -> CGFloat { img.size.height / 2 }
    private func interior(_ img: NSImage) -> NSRect { NSRect(x: 3.1, y: cy(img) - 5.4, width: 27.8, height: 10.8) }
    /// The band the eyes sit in, clear of the mouth (and of the straw while charging).
    private func eyeBand(_ img: NSImage, from: CGFloat = 0.3, x: ClosedRange<CGFloat> = 3.1...30.9) -> NSRect {
        NSRect(x: x.lowerBound, y: cy(img) + from, width: x.upperBound - x.lowerBound, height: 3.6 - from)
    }

    func testEyesAreSmallDotsSetWide() {
        let img = volta()
        let left = ink(img, in: eyeBand(img, x: 3.1...cx)), right = ink(img, in: eyeBand(img, x: cx...30.9))
        XCTAssertEqual(right.cx - left.cx, 13.0, accuracy: 0.4)
        for eye in [left, right] { XCTAssertEqual(eye.count, 4.9, accuracy: 0.9) }   // a 2.4 × 2.6 dot
    }

    func testMouthIsWideAndShallow() {
        let img = volta()   // 0% charge: a frown 0.9 deep
        let mouth = ink(img, in: NSRect(x: 3.1, y: cy(img) - 3.0, width: 27.8, height: 3.2))
        XCTAssertEqual(mouth.width, 9.1, accuracy: 0.5)   // 8 across plus round caps
        XCTAssertLessThan(mouth.height, 2.4)
    }

    func testGazeTurnsTheWholeFace() {
        let img = volta()
        let still = ink(img, in: interior(img)).cx
        XCTAssertEqual(ink(volta(idle: .init(gaze: 1)), in: interior(img)).cx - still, 2.0, accuracy: 0.15)
        XCTAssertEqual(ink(volta(idle: .init(gaze: -1)), in: interior(img)).cx - still, -2.0, accuracy: 0.15)
    }

    func testBreathLiftsTheFace() {
        let img = volta()
        XCTAssertEqual(ink(volta(idle: .init(breath: 1)), in: interior(img)).cy - ink(img, in: interior(img)).cy,
                       0.25, accuracy: 0.06)
        let full = volta(plugged: true)
        let band = NSRect(x: cx - 8.5, y: cy(full) - 4.0, width: 17, height: 7.6)   // clear of the glow
        XCTAssertEqual(ink(volta(plugged: true, idle: .init(breath: 1)), in: band).cy - ink(full, in: band).cy,
                       0.35, accuracy: 0.06)
    }

    func testBlinkAndYawnShutTheEyes() {
        let img = volta()
        let open = ink(img, in: eyeBand(img)).height
        XCTAssertLessThan(ink(volta(idle: .init(blink: 1)), in: eyeBand(img)).height, open * 0.7)
        XCTAssertLessThan(ink(volta(idle: .init(yawn: 1)), in: eyeBand(img)).height, open * 0.7)
    }

    func testYawnOpensTheMouthDown() {
        let img = volta()
        let band = NSRect(x: 3.1, y: cy(img) - 6.0, width: 27.8, height: 6.2)
        XCTAssertLessThan(ink(volta(idle: .init(yawn: 1)), in: band).cy, ink(img, in: band).cy - 1.0)
    }

    func testTiredLidsCutTheTopsOffTheDots() {
        let img = volta()
        let open = ink(img, in: eyeBand(img)), tired = ink(volta(idle: .init(tired: 1)), in: eyeBand(img))
        XCTAssertLessThan(tired.height, open.height * 0.8)
        XCTAssertLessThan(tired.count, open.count)
    }

    func testPeekingOpensHisDrinkingEyes() {
        let img = volta(charging: true, plugged: true)
        let band = eyeBand(img, from: 0.9)
        XCTAssertLessThan(ink(volta(charging: true, plugged: true, idle: .init(peek: 1)), in: band).count,
                          ink(img, in: band).count * 0.8)   // dots are less ink than ^ ^
    }

    func testStirringOpensHisSleepyEyes() {
        let img = volta(plugged: true)
        let band = eyeBand(img, x: (cx - 8.5)...(cx + 8.5))
        XCTAssertGreaterThan(ink(volta(plugged: true, idle: .init(doze: 0)), in: band).cy,
                             ink(img, in: band).cy + 0.25)   // dots sit higher than ‿ ‿
    }

    func testTheCasingStaysPutWhenHisFaceTurns() {
        let age = BatteryGlyph.age(health: 60)   // cracked, band-aid, dripping
        let img = volta(age: age)
        let casing = NSRect(x: 2, y: cy(img) - 6, width: 3.5, height: 12)
        XCTAssertEqual(ink(volta(age: age, idle: .init(gaze: 1)), in: casing).count, ink(img, in: casing).count,
                       accuracy: ink(img, in: casing).count * 0.01)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter GlyphFaceTests 2>&1 | grep -E "error:|Executed" | head`
Expected: the build fails with `type 'BatteryGlyph' has no member 'Idle'` (and
`extra argument 'idle'`).

- [ ] **Step 4: Add `Idle` and the parameter**

In `BatteryGlyph.swift`, insert after `public static func age(health: Double?) -> CGFloat { … }`:

```swift
    /// What Volta's idle (`IdleDriver` in BatteryTimeCore) has him doing, as
    /// drawn here. Its own small type so this file still compiles on its own:
    /// the Menumon site's render-glyphs.sh builds it alone.
    public struct Idle {
        /// −1…1: every face feature shifts 2pt per unit sideways.
        public var gaze: CGFloat
        /// −1…1: every face feature rises 0.25pt per unit (0.35pt when full).
        public var breath: CGFloat
        /// 0…1: the dots squash shut (merges with the minute cue's blink).
        public var blink: CGFloat
        /// 0…1: the mouth opens into a tall oval and the eyes shut with it.
        public var yawn: CGFloat
        /// 0…1, full only: 1 is ‿ ‿; below that the eyes open to dots.
        public var doze: CGFloat
        /// 0…1, charging only: 0 is ^ ^; above that the eyes open to dots.
        public var peek: CGFloat
        /// 0…1: lids droop by up to a third.
        public var tired: CGFloat

        public init(gaze: CGFloat = 0, breath: CGFloat = 0, blink: CGFloat = 0, yawn: CGFloat = 0,
                    doze: CGFloat = 1, peek: CGFloat = 0, tired: CGFloat = 0) {
            self.gaze = gaze; self.breath = breath; self.blink = blink; self.yawn = yawn
            self.doze = doze; self.peek = peek; self.tired = tired
        }

        /// No idle: he looks exactly as he would without one.
        public static let still = Idle()
    }
```

Change the signature's last parameter from `age: CGFloat = 0` to:

```swift
        age: CGFloat = 0,
        idle: Idle = .still
```

and add this line to the comment block under `// Not animated:`:

```swift
        // - idle: what his idle has him doing (`Idle`); `.still` when off.
```

- [ ] **Step 5: Replace the eyes**

Replace everything from `let eye = bodyH * 0.15` through the closing `}` of
the eye `if drinking { … } else if stuffed { … } else if shut > 0.85 { … } else { … }`
chain (the line before `let mouthY = cy - bodyH * 0.12`) with:

```swift
                // BMO's proportions: small dot eyes set wide, a wide shallow
                // mouth. `eye` is a dot's height (the unit the age lines are
                // sized in), `eyeW` its width, `eyeY` its bottom edge.
                let eye = bodyH * 0.153, eyeW = bodyH * 0.141
                let low = fillKind == .red
                let eyeY = cy + bodyH * 0.112 - eye / 2
                let eyeOffset = bodyW * 0.191
                let eyeXs = [cx - eyeOffset, cx + eyeOffset]
                let mouthLW = max(0.9, bodyH * 0.08)
                // Shapes knocked out of (or inked over) the fill, and anything
                // drawn on top afterwards in its own colours.
                var strokes: [NSBezierPath] = []
                var fills: [NSBezierPath] = []

                // How shut his eyes are: the minute cue's blink (closed for the
                // middle of `blink`), the idle's blinks, and a yawn squeezing them.
                let cueShut: CGFloat = {
                    guard let b = blink else { return 0 }
                    return b < 0.35 ? b / 0.35 : b < 0.5 ? 1 : max(0, 1 - (b - 0.5) / 0.4)
                }()
                var shut = max(cueShut, idle.blink, drinking ? 0 : idle.yawn)
                // Heavy lids, as a fraction of a dot cut off its top: a
                // grandpa's, or tired ones at low charge.
                let lid = max(0.45 * grandpa, 0.33 * idle.tired)
                // Falling apart, his right eye is an ✕.
                let xEye = falling > 0.35
                let eyesShown = xEye ? [eyeXs[0]] : eyeXs
                if xEye {
                    let ex = eyeXs[1], r = eye * 0.55
                    for d in [-1.0, 1.0] as [CGFloat] {
                        let e = NSBezierPath()
                        e.move(to: NSPoint(x: ex - r, y: eyeY + eye / 2 - d * r))
                        e.line(to: NSPoint(x: ex + r, y: eyeY + eye / 2 + d * r))
                        e.lineWidth = mouthLW * 0.85; e.lineCapStyle = .round
                        strokes.append(e)
                    }
                }

                // His eyes are dots, except drinking (^ ^, opening to dots as
                // he peeks) and full (‿ ‿, opening to dots as he stirs).
                var dots = !drinking && !stuffed
                if drinking, idle.peek > 0.15 { dots = true; shut = max(shut, 1 - idle.peek) }
                if stuffed, idle.doze <= 0.85 { dots = true; shut = max(shut, idle.doze) }
                if !dots && drinking {
                    for ex in eyesShown {                              // happy ^ ^
                        let e = NSBezierPath()
                        e.move(to: NSPoint(x: ex - eye * 0.8, y: eyeY + eye * 0.2))
                        e.line(to: NSPoint(x: ex, y: eyeY + eye * 1.0))
                        e.line(to: NSPoint(x: ex + eye * 0.8, y: eyeY + eye * 0.2))
                        e.lineWidth = mouthLW; e.lineCapStyle = .round; e.lineJoinStyle = .round
                        strokes.append(e)
                    }
                } else if !dots && stuffed {
                    for ex in eyesShown {                              // contented ‿ ‿
                        let e = NSBezierPath()
                        e.appendArc(withCenter: NSPoint(x: ex, y: eyeY + eye * 0.9), radius: eye * 0.75,
                                    startAngle: 200, endAngle: 340, clockwise: false)
                        e.lineWidth = mouthLW; e.lineCapStyle = .round
                        strokes.append(e)
                    }
                } else if shut > 0.85 {
                    for ex in eyesShown {                              // shut: a line
                        let e = NSBezierPath()
                        e.move(to: NSPoint(x: ex - eye * 0.6, y: eyeY + eye / 2))
                        e.line(to: NSPoint(x: ex + eye * 0.6, y: eyeY + eye / 2))
                        e.lineWidth = mouthLW; e.lineCapStyle = .round
                        strokes.append(e)
                    }
                } else {
                    let h = eye * (1 - shut)
                    for ex in eyesShown {
                        if shut == 0, lid > 0 {
                            // a dot cut flat across the top
                            let r = eye / 2
                            let th = asin(max(-1, min(1, (r - lid * eye) / r))) * 180 / .pi
                            let e = NSBezierPath()
                            e.appendArc(withCenter: .zero, radius: r, startAngle: th, endAngle: 180 - th, clockwise: true)
                            e.close()
                            var t = AffineTransform(translationByX: ex, byY: eyeY + r)
                            t.scale(x: eyeW / eye, y: 1)
                            e.transform(using: t)
                            fills.append(e)
                        } else {
                            fills.append(NSBezierPath(ovalIn: NSRect(x: ex - eyeW / 2, y: eyeY + (eye - h) / 2,
                                                                     width: eyeW, height: max(0.6, h))))
                        }
                    }
                }
```

- [ ] **Step 6: Replace the mouth**

Replace everything from `let mouthY = cy - bodyH * 0.12` through the closing
`}` of the mouth chain (the line before `// Age lines:`) with:

```swift
                // The lips round the straw and the full mouth sit at `mouthY`.
                // BMO's mouth is 8 across, its ends 1.8 below centre.
                let mouthY = cy - bodyH * 0.12
                let mouthHalfW = bodyH * 0.235, mouthEndY = cy - bodyH * 0.106
                if idle.yawn > 0.15 && !drinking {
                    // A yawn: the mouth opens into a tall oval.
                    let w = bodyH * 0.212, h = max(bodyH * 0.065, bodyH * 0.247 * idle.yawn)
                    fills.append(NSBezierPath(ovalIn: NSRect(x: cx - w / 2, y: cy - bodyH * 0.07 - h, width: w, height: h)))
                } else if drinking {
                    // Lips pursed round the straw, swelling a touch as each sip
                    // arrives.
                    let gulp: CGFloat = sip.map(gulp) ?? 0
                    let r = bodyH * (0.085 + 0.035 * gulp)
                    fills.append(NSBezierPath(ovalIn: NSRect(x: cx - r, y: mouthY - r, width: r * 2, height: r * 2)))
                } else if stuffed {
                    // A small closed mouth. The burp opens it for a moment.
                    let b = burp ?? 0
                    if b > 0.2 && b < 0.75 {
                        let r = bodyH * 0.07
                        fills.append(NSBezierPath(ovalIn: NSRect(x: cx - r, y: mouthY - r, width: r * 2, height: r * 2)))
                    } else {
                        let m = NSBezierPath()
                        m.move(to: NSPoint(x: cx - bodyH * 0.06, y: mouthY)); m.line(to: NSPoint(x: cx + bodyH * 0.06, y: mouthY))
                        m.lineWidth = mouthLW; m.lineCapStyle = .round
                        strokes.append(m)
                    }
                } else if slosh != nil {
                    // BMO's open D grin while his charge sloshes about.
                    let d = NSBezierPath()
                    d.appendArc(withCenter: .zero, radius: 1, startAngle: 180, endAngle: 360)
                    d.close()
                    var t = AffineTransform(translationByX: cx, byY: cy - bodyH * 0.082)
                    t.scale(x: bodyH * 0.206, y: bodyH * 0.188)
                    d.transform(using: t)
                    fills.append(d)
                } else {
                    // A smile from 60%, flat from 35%, a frown below (and
                    // whenever the fill is red).
                    let depth: CGFloat = low || pctValue < 35 ? -bodyH * 0.053 : pctValue >= 60 ? bodyH * 0.106 : 0
                    let mouth = NSBezierPath()
                    mouth.move(to: NSPoint(x: cx - mouthHalfW, y: mouthEndY))
                    mouth.curve(to: NSPoint(x: cx + mouthHalfW, y: mouthEndY),
                                controlPoint1: NSPoint(x: cx - mouthHalfW * 0.5, y: mouthEndY - depth * 1.33),
                                controlPoint2: NSPoint(x: cx + mouthHalfW * 0.5, y: mouthEndY - depth * 1.33))
                    mouth.lineWidth = bodyH * 0.065; mouth.lineCapStyle = .round
                    strokes.append(mouth)
                }
```

- [ ] **Step 7: Re-anchor the age lines and shift the face**

In the `// Age lines:` block, make these two replacements.

Crow's feet now follow the wider eyes:
`let x0 = cx + side * (bodyW * 0.17 + eye * 0.95)` →
`let x0 = cx + side * (eyeOffset + eye * 0.95)`

Laugh lines now sit just outside the wider mouth:
`let x0 = cx + side * bodyH * 0.3` →
`let x0 = cx + side * (mouthHalfW + bodyH * 0.065)`

Then insert just above `let draw = {`:

```swift
                // The idle turns his face (gaze) and lifts it as he breathes.
                // The casing's crack, band-aid and drips stay put.
                let faceDX = idle.gaze * 2, faceDY = idle.breath * (stuffed ? 0.35 : 0.25)
                if faceDX != 0 || faceDY != 0 {
                    let t = AffineTransform(translationByX: faceDX, byY: faceDY)
                    for p in fills + strokes { p.transform(using: t) }
                }
```

The straw is attached to his mouth, so it follows. Change
`drawStraw(mouth: NSPoint(x: cx, y: mouthY), bodyH: bodyH, sip: sip)` to:

```swift
                    drawStraw(mouth: NSPoint(x: cx + faceDX, y: mouthY + faceDY), bodyH: bodyH, sip: sip)
```

and in the burp bubble change
`let at = NSPoint(x: cx + bodyW * 0.08 + u * bodyW * 0.12, y: mouthY + u * bodyH * 0.45)` to:

```swift
                    let at = NSPoint(x: cx + faceDX + bodyW * 0.08 + u * bodyW * 0.12, y: mouthY + faceDY + u * bodyH * 0.45)
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `swift test 2>&1 | grep -E "error:|failed|Suite 'All tests'" | head`
Expected: two `Suite 'All tests' passed` lines: `GlyphFaceTests` (10),
`VoltaAgeTests` (5), and the core suites.

- [ ] **Step 9: Check the file still compiles on its own**

Run: `cd "$(mktemp -d)" && cp /Users/nicholassmith/Code/battery-time-menubar/Sources/BatteryTime/BatteryGlyph.swift . && printf 'import AppKit\n_ = BatteryGlyph.image(pct: 50, charging: false, lead: "", trailing: "", ink: .white, fill: .none, face: true)\n' > main.swift && swiftc BatteryGlyph.swift main.swift -o t 2>&1 | grep -c error: ; cd - >/dev/null`
Expected: `0`.

- [ ] **Step 10: Commit**

```bash
git add Sources/BatteryTime/BatteryGlyph.swift Tests/BatteryTimeTests/Raster.swift Tests/BatteryTimeTests/GlyphFaceTests.swift
git commit -m "Volta's BMO face, and drawing his idle [no release]

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Wiring the clock, mood, cue and setting

**Files:**
- Create: `Sources/BatteryTimeCore/VoltaMotion.swift`, `Tests/BatteryTimeCoreTests/VoltaMotionTests.swift`
- Modify: `Sources/BatteryTime/main.swift` (properties ~lines 40–57,
  `applicationDidFinishLaunching` ~74–96, `render` ~168–232, the
  Settings footer ~313–327, `updateSipLoop` ~363–377)
- Modify: `Sources/BatteryTime/DisplayPrefs.swift`

**Interfaces:**
- Consumes:
  - `IdleDriver`, `IdleMood`, `IdlePose` (Task 1);
  - `BatteryGlyph.Idle` and `image(..., idle:)` (Task 2).
- Produces:
  - `public func idleMood(charging: Bool, plugged: Bool, pct: Int) -> IdleMood`
  - `public func voltaMayMove(faceShown: Bool, reduceMotion: Bool, displayAsleep: Bool, sessionActive: Bool) -> Bool`
  - `public func animationDelay(idleTick: TimeInterval?, drinking: Bool) -> TimeInterval?`
  - `DisplayPrefs.animateFace: Bool` (key `animateFace`, default true)

- [ ] **Step 1: Write the failing tests**

Create `Tests/BatteryTimeCoreTests/VoltaMotionTests.swift`:

```swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import BatteryTimeCore

final class VoltaMotionTests: XCTestCase {
    func testMoodFollowsThePowerState() {
        XCTAssertEqual(idleMood(charging: true, plugged: true, pct: 50), .drinking)
        XCTAssertEqual(idleMood(charging: false, plugged: true, pct: 100), .sleepy)
        XCTAssertEqual(idleMood(charging: false, plugged: false, pct: 21), .awake(tired: false))
        XCTAssertEqual(idleMood(charging: false, plugged: false, pct: 20), .awake(tired: true))
    }

    func testNothingMovesWhenHeCantBeSeen() {
        XCTAssertTrue(voltaMayMove(faceShown: true, reduceMotion: false, displayAsleep: false, sessionActive: true))
        XCTAssertFalse(voltaMayMove(faceShown: false, reduceMotion: false, displayAsleep: false, sessionActive: true))
        XCTAssertFalse(voltaMayMove(faceShown: true, reduceMotion: false, displayAsleep: true, sessionActive: true))
        XCTAssertFalse(voltaMayMove(faceShown: true, reduceMotion: false, displayAsleep: false, sessionActive: false))
        XCTAssertNil(animationDelay(idleTick: nil, drinking: false))
    }

    func testReduceMotionStillsHim() {
        XCTAssertFalse(voltaMayMove(faceShown: true, reduceMotion: true, displayAsleep: false, sessionActive: true))
    }

    func testSipLoopRunsWithoutTheIdle() {
        XCTAssertEqual(animationDelay(idleTick: nil, drinking: true), 1.0 / 12)
    }

    func testTheSoonerOfIdleAndSipWins() {
        XCTAssertEqual(animationDelay(idleTick: 0.25, drinking: false), 0.25)
        XCTAssertEqual(animationDelay(idleTick: 0.25, drinking: true), 1.0 / 12)
        XCTAssertEqual(animationDelay(idleTick: 1.0 / 15, drinking: true), 1.0 / 15)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter VoltaMotionTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'idleMood' in scope`.

- [ ] **Step 3: Write `VoltaMotion.swift`**

```swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Volta's idle mood for a reading: charging → drinking; plugged in and not
/// charging → sleepy; on battery → awake, tired at 20% and below.
public func idleMood(charging: Bool, plugged: Bool, pct: Int) -> IdleMood {
    if charging { return .drinking }
    if plugged { return .sleepy }
    return .awake(tired: pct <= 20)
}

/// Whether Volta may move at all: his face is showing, Reduce Motion is off,
/// and someone could be looking (display awake, session active).
public func voltaMayMove(faceShown: Bool, reduceMotion: Bool, displayAsleep: Bool, sessionActive: Bool) -> Bool {
    faceShown && !reduceMotion && !displayAsleep && sessionActive
}

/// How long until Volta next needs drawing: the idle's next tick (nil when
/// the idle is off) or, while he drinks, the sip loop's 1/12 s, whichever is
/// sooner. Nil when nothing moves.
public func animationDelay(idleTick: TimeInterval?, drinking: Bool) -> TimeInterval? {
    [idleTick, drinking ? 1.0 / 12 : nil].compactMap { $0 }.min()
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter VoltaMotionTests 2>&1 | grep -E "error:|Executed" | head -3`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Add the pref**

In `DisplayPrefs.swift`, add `private static let kAnimateFace = "animateFace"`
after `kShowFace`, and after the `showFace` property add:

```swift
    /// Volta's idle (glances, breaths, blinks, yawns). Off, he moves only for
    /// the sip loop and the twice-a-minute cue.
    static var animateFace: Bool {
        get { boolOr(kAnimateFace, true) }
        set { defaults.set(newValue, forKey: kAnimateFace) }
    }
```

- [ ] **Step 6: Wire `main.swift`**

1. Replace these properties:

```swift
    private static let sipPeriod = BatteryGlyph.sipPeriod
    private var sipTimer: Timer?
    private var sipStarted = Date()
```

with:

```swift
    private static let sipPeriod = BatteryGlyph.sipPeriod
    /// One clock for all of Volta's motion, his idle and the sip loop: a
    /// one-shot timer re-armed after every draw while something still moves.
    private var animTimer: Timer?
    private var idle = IdleDriver(seed: UInt64.random(in: 0...UInt64.max), mood: .awake(tired: false),
                                  at: ProcessInfo.processInfo.systemUptime)
    /// When the current sip loop began; nil while he isn't drinking.
    private var sipStarted: Date?
    private var displayAsleep = false
    private var sessionActive = true
```

2. In `minuteAnimation`'s `completion:` closure, add this before
`self?.rerender()`:

```swift
        self?.idle.setCue(playing: false, at: ProcessInfo.processInfo.systemUptime)
```

   In the `MinuteCue { … }` closure, add this before
   `self.minuteAnimation.start()`:

```swift
            self.idle.setCue(playing: true, at: ProcessInfo.processInfo.systemUptime)
```

3. At the end of `applicationDidFinishLaunching`, add:

```swift
        // Nobody sees the menu bar while the display sleeps or another user
        // has the session, so Volta stops drawing until they're back.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.displayAsleep = true; self?.rerender()
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.displayAsleep = false; self?.rerender()
        }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = false; self?.rerender()
        }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = true; self?.rerender()
        }
```

4. In `render`, replace the `updateSipLoop(face && isCharging)` line with:

```swift
            let now = ProcessInfo.processInfo.systemUptime
            let moving = voltaMayMove(faceShown: face,
                                      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                      displayAsleep: displayAsleep, sessionActive: sessionActive)
            let drinking = moving && isCharging
            if drinking { if sipStarted == nil { sipStarted = Date() } } else { sipStarted = nil }
            let idling = moving && DisplayPrefs.animateFace
            idle.setMood(idleMood(charging: isCharging, plugged: snap.reading.plugged, pct: pct!), at: now)
```

   Replace the `sip:` argument:

```swift
                sip: sipStarted.map { CGFloat(Date().timeIntervalSince($0)
                    .truncatingRemainder(dividingBy: Self.sipPeriod) / Self.sipPeriod) },
```

   Add a comma after the `age:` argument, then append:

```swift
                idle: idling ? BatteryGlyph.Idle(idle.pose(at: now)) : .still
```

   After `controller.setIcon(image)` in the glyph branch, add:

```swift
            scheduleAnimation(after: animationDelay(idleTick: idling ? idle.nextTick(after: now) : nil,
                                                    drinking: drinking))
```

   In the text-fallback `else` branch, add this before
   `controller.setTitle(text, warn: false)`:

```swift
            sipStarted = nil
            scheduleAnimation(after: nil)
```

5. Replace the whole `updateSipLoop(_:)` function, with its doc comment, by:

```swift
    /// Re-arms Volta's clock to draw again after `delay`, or stops it (nil).
    /// The 10% tolerance lets macOS coalesce the wakeups.
    private func scheduleAnimation(after delay: TimeInterval?) {
        animTimer?.invalidate()
        animTimer = nil
        guard let delay else { return }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.animTimer = nil
            self?.rerender()
        }
        t.tolerance = delay * 0.1
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }
```

6. In the Settings footer, after the `"Time remaining"` toggle, add:

```swift
            sub.addItem(.separator())
            self.addToggle(sub, title: "Animate Volta", on: DisplayPrefs.animateFace) { DisplayPrefs.animateFace = $0 }
```

7. At the end of `main.swift`, outside the class, add:

```swift
private extension BatteryGlyph.Idle {
    init(_ p: IdlePose) {
        self.init(gaze: CGFloat(p.gaze), breath: CGFloat(p.breath), blink: CGFloat(p.blink), yawn: CGFloat(p.yawn),
                  doze: CGFloat(p.doze), peek: CGFloat(p.peek), tired: CGFloat(p.tired))
    }
}
```

- [ ] **Step 7: Build, test, and check nothing still uses `sipTimer`**

Run: `swift build 2>&1 | grep -E "error|Build complete"; grep -n "sipTimer\|updateSipLoop" Sources/BatteryTime/main.swift; swift test 2>&1 | grep -E "Suite 'All tests' (passed|failed)|with [1-9][0-9]* failures"`
Expected: `Build complete!`, no grep hits, two `passed` lines.

- [ ] **Step 8: Commit**

```bash
git add Sources/BatteryTimeCore/VoltaMotion.swift Tests/BatteryTimeCoreTests/VoltaMotionTests.swift Sources/BatteryTime/main.swift Sources/BatteryTime/DisplayPrefs.swift
git commit -m "Volta idles: one animation clock, mood and cue hooks, Animate Volta [no release]

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Verify: look, motion, energy

**Files:**
- Create: `Tests/BatteryTimeTests/GlyphPerformanceTests.swift`
- Scratch only, not committed: the renderers below, under
  `$SCRATCH=/private/tmp/claude-501/-Users-nicholassmith-Code-battery-time-menubar/471c82e0-9dc4-41d7-a75d-91b9383f7620/scratchpad/idle`

**Interfaces:**
- Consumes:
  - `BatteryGlyph.image(..., idle:)` and `BatteryGlyph.Idle` (Task 2);
  - `IdleDriver` and `IdlePose` (Task 1);
  - `rasterize(_:scale:)` (Task 2's `Raster.swift`).
- Produces: a commit with the performance test, plus images and numbers for
  Nick.

- [ ] **Step 1: Write the performance test**

```swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
import AppKit
@testable import BatteryTime

final class GlyphPerformanceTests: XCTestCase {
    /// The idle redraws ~6 times a second on average; each frame must stay
    /// cheap for the energy budget (< 0.5% of a core).
    func testAFrameDrawsInUnderTwoMilliseconds() {
        let frames = 300
        let start = Date()
        for i in 0..<frames {
            let idle = BatteryGlyph.Idle(gaze: sin(Double(i) / 10), breath: cos(Double(i) / 7), blink: i % 30 == 0 ? 1 : 0)
            let img = BatteryGlyph.image(pct: 40 + i % 50, charging: false, lead: "62%", trailing: "1:10", ink: .white,
                                         fill: .none, face: true, age: 0.5, idle: idle)
            _ = rasterize(img, scale: 2)
        }
        let perFrame = Date().timeIntervalSince(start) / Double(frames)
        print("glyph frame: \(String(format: "%.3f", perFrame * 1000)) ms")
        XCTAssertLessThan(perFrame, 0.002)
    }
}
```

Run: `swift test -c release -Xswiftc -enable-testing --filter GlyphPerformanceTests 2>&1 | grep -E "glyph frame|passed|failed"`
Expected: a `glyph frame: 0.xxx ms` line and `passed`. Note the number for
the report.

- [ ] **Step 2: Commit**

```bash
git add Tests/BatteryTimeTests/GlyphPerformanceTests.swift
git commit -m "Glyph frame cost test [no release]

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Render the review sheet**

Create `$SCRATCH/sheet/main.swift`, then compile it with the glyph and the
driver:

```swift
import AppKit
// Every state × idle pose × aging stage, dark then light, at a given scale.
let poses: [(String, BatteryGlyph.Idle)] = [("still", .still), ("gaze ←", .init(gaze: -1)), ("gaze →", .init(gaze: 1)),
    ("blink", .init(blink: 1)), ("yawn", .init(yawn: 1)), ("tired", .init(tired: 1)),
    ("peek", .init(peek: 1)), ("stir", .init(doze: 0)), ("breath", .init(breath: 1))]
let states: [(String, Int, Bool, Bool, BatteryFill)] = [("battery", 80, false, false, .none), ("half", 45, false, false, .none),
    ("low", 12, false, false, .red), ("charging", 40, true, true, .none), ("full", 100, false, true, .none)]
let healths: [Double] = [100, 80, 60, 40]
let scale = CGFloat(Double(CommandLine.arguments[2])!)
let cellW: CGFloat = 46, cellH: CGFloat = 26, labelW: CGFloat = 70
let rows = states.count * healths.count
let half = cellW * CGFloat(poses.count)
let W = labelW + half * 2, H = cellH * CGFloat(rows) + 12
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
NSColor(white: 0.12, alpha: 1).setFill(); NSRect(x: labelW, y: 0, width: half, height: H).fill()
NSColor(white: 0.92, alpha: 1).setFill(); NSRect(x: labelW + half, y: 0, width: half, height: H).fill()
let font: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 6)]
for (d, base) in [(true, labelW), (false, labelW + half)] {
    for (i, p) in poses.enumerated() {
        var a = font; a[.foregroundColor] = d ? NSColor.white : NSColor.black
        NSAttributedString(string: p.0, attributes: a).draw(at: NSPoint(x: base + CGFloat(i) * cellW + 12, y: H - 9))
    }
}
var r = 0
for s in states { for h in healths {
    let y = H - 12 - CGFloat(r + 1) * cellH; r += 1
    NSAttributedString(string: "\(s.0) · \(Int(h))%", attributes: font).draw(at: NSPoint(x: 3, y: y + 9))
    for (dark, ink) in [(true, NSColor.white), (false, NSColor.black)] {
        for (i, p) in poses.enumerated() {
            let img = BatteryGlyph.image(pct: s.1, charging: s.2, plugged: s.3, lead: "", trailing: "", ink: ink,
                                         fill: s.4, face: true, sip: s.2 ? 0.3 : nil, age: BatteryGlyph.age(health: h), idle: p.1)
            img.draw(in: NSRect(x: labelW + (dark ? 0 : half) + CGFloat(i) * cellW + 4, y: y + (cellH - img.size.height) / 2,
                                width: img.size.width, height: img.size.height))
        }
    }
}}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
```

Run:
```bash
SCRATCH=/private/tmp/claude-501/-Users-nicholassmith-Code-battery-time-menubar/471c82e0-9dc4-41d7-a75d-91b9383f7620/scratchpad/idle
cd $SCRATCH/sheet && cp ~/Code/battery-time-menubar/Sources/BatteryTime/BatteryGlyph.swift . \
  && swiftc -O BatteryGlyph.swift main.swift -o sheet 2>&1 | grep error; ./sheet $SCRATCH/sheet-2x.png 2 && ./sheet $SCRATCH/sheet-5x.png 5
```

Read both PNGs and check every cell by eye:
- the dots, the wide mouth and the D grin read at 2×;
- gaze moves the face but not the crack, band-aid or drips;
- the yawn oval doesn't hit the laugh lines;
- peek only changes the charging row, and stir only the full row.

Fix and re-render anything that's off before going on.

- [ ] **Step 4: Render the animated preview**

Create `$SCRATCH/anim/main.swift`:

```swift
import AppKit
// 20 s of each state's idle at 15 fps, three rows on a dark bar, 4×, one PNG per frame.
let scale: CGFloat = 4, fps = 15.0, seconds = 20.0
let rows: [(String, Int, Bool, Bool, IdleMood)] = [("on battery", 80, false, false, .awake(tired: false)),
    ("charging", 40, true, true, .drinking), ("full", 100, false, true, .sleepy)]
var drivers = rows.enumerated().map { IdleDriver(seed: UInt64(41 + $0.offset), mood: $0.element.4, at: 0) }
let W: CGFloat = 60, H: CGFloat = 26 * CGFloat(rows.count)
let out = CommandLine.arguments[1]
for f in 0..<Int(fps * seconds) {
    let t = Double(f) / fps
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(srgbRed: 38/255, green: 38/255, blue: 42/255, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    for (i, row) in rows.enumerated() {
        let p = drivers[i].pose(at: t)
        let idle = BatteryGlyph.Idle(gaze: CGFloat(p.gaze), breath: CGFloat(p.breath), blink: CGFloat(p.blink), yawn: CGFloat(p.yawn),
                                     doze: CGFloat(p.doze), peek: CGFloat(p.peek), tired: CGFloat(p.tired))
        let sip = row.2 ? CGFloat(t.truncatingRemainder(dividingBy: BatteryGlyph.sipPeriod) / BatteryGlyph.sipPeriod) : nil
        let img = BatteryGlyph.image(pct: row.1, charging: row.2, plugged: row.3, lead: "", trailing: "", ink: .white,
                                     fill: .none, face: true, sip: sip, idle: idle)
        img.draw(in: NSRect(x: 10, y: H - CGFloat(i + 1) * 26 + (26 - img.size.height) / 2, width: img.size.width, height: img.size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: String(format: "%@/f%04d.png", out, f)))
}
```

Run:
```bash
cd $SCRATCH/anim && mkdir -p frames && cp ~/Code/battery-time-menubar/Sources/BatteryTime/BatteryGlyph.swift ~/Code/battery-time-menubar/Sources/BatteryTimeCore/IdleDriver.swift . \
  && swiftc -O BatteryGlyph.swift IdleDriver.swift main.swift -o anim 2>&1 | grep error; ./anim $SCRATCH/anim/frames \
  && python3 -I -c "
from PIL import Image; import glob
fs=[Image.open(p) for p in sorted(glob.glob('$SCRATCH/anim/frames/f*.png'))]
fs[0].save('$SCRATCH/volta-idle.png', save_all=True, append_images=fs[1:], duration=67, loop=0)
" && open -a Safari $SCRATCH/volta-idle.png
```

Expected: Safari plays the three rows. Watch it through:
- on battery: glances, blinks, breathing, and a yawn only if one falls in the
  20 s;
- charging: sipping with peeks;
- full: dozing, plus a stir if one falls in the 20 s.

If a stir or yawn doesn't show up, re-run with other seeds until one does.

- [ ] **Step 5: Measure the running app's CPU**

```bash
cd ~/Code/battery-time-menubar && scripts/build-app.sh >/dev/null && osascript -e 'quit app "Battery Time"'; sleep 2
open "build/Battery Time.app"; sleep 5
PID=$(pgrep -f "build/Battery Time.app/Contents/MacOS" | head -1)
defaults write com.nicholaspsmith.BatteryTime animateFace -bool true; sleep 10
top -l 31 -s 2 -pid $PID -stats cpu | awk '/^[0-9.]+$/{s+=$1;n++} END{printf "idle on: %.2f%% avg over %d samples\n", s/n, n}'
defaults write com.nicholaspsmith.BatteryTime animateFace -bool false; sleep 10
top -l 31 -s 2 -pid $PID -stats cpu | awk '/^[0-9.]+$/{s+=$1;n++} END{printf "idle off: %.2f%% avg over %d samples\n", s/n, n}'
defaults delete com.nicholaspsmith.BatteryTime animateFace
pmset -g batt | head -2
osascript -e 'quit app "Battery Time"'; sleep 2; open "$HOME/Applications/Battery Time.app"
```

Expected: `idle on` stays under 0.5%. Note the power state `pmset` reports
(charging, full or on battery), since that sets which idle was measured. If
it's over budget, profile with `sample $PID 5` and fix it before going on.

---

### Task 5: Docs, images and release

**Files:**
- Modify: `README.md`, `CHANGELOG.md`
- Regenerate: `screenshots/*.png` (7 files), `docs/menubar-icon.png`,
  `docs/animation.png`
- After Nick approves: the site images in `~/Code/widgets.nicksmith.software`

**Interfaces:**
- Consumes: `BatteryGlyph.image(..., idle:)` (Task 2).
- Produces: release 1.11.0.

- [ ] **Step 1: README**

Make these edits.

The version line `**Version 1.10.0**` → `**Version 1.11.0**`.

Replace the paragraph starting `By default the battery has a face — Volta`
(through `so it stays visible.`) with:

```markdown
By default the battery has a face: Volta, a digital face in BMO's proportions
(Settings ▸ **Battery face** turns it off). On battery his mouth follows the
charge: a smile from 60%, flat from 35%, a frown below that. Where the face
crosses the empty part of the battery it is drawn in the menu-bar ink so it
stays visible.

He's never quite still. On battery he glances side to side, blinks, breathes
and now and then yawns, more often and with drooping lids at 20% and below.
Charging, he keeps sipping and peeks out between gulps. Full, he dozes,
stirring every minute or so for a look round and a yawn. Settings ▸ **Animate
Volta** turns the idle off, Reduce Motion stills him entirely, and he stops
drawing while the display sleeps.
```

Change the table row `| Worn battery (health 80% or less) |` to
`| Worn battery (health 60%) |`.

Replace `with the face on, Volta is full: eyes contentedly closed, glowing yellow.`
with `with the face on, Volta is full: dozing, glowing yellow.`

Replace:

```markdown
Now and then Volta blinks while his charge sloshes from side to side, or,
when stuffed, burps.
```

with:

```markdown
Twice a minute Volta blinks and grins while his charge sloshes from side to
side, or, when stuffed, burps.
```

Replace:

```markdown
counting only the ones that are running. The animation and the sip are
skipped when Reduce Motion is on.
```

with:

```markdown
counting only the ones that are running. His idle pauses while it plays. All
of his motion stops when Reduce Motion is on.
```

- [ ] **Step 2: CHANGELOG**

Insert above `## [1.10.0] - 2026-10-14`:

```markdown
## [1.11.0] - 2026-10-15

- Volta has a new face in BMO's proportions: small dot eyes set wide and a wide, shallow mouth, with an open D grin when his charge sloshes
- He idles all the time. On battery he glances side to side, blinks, breathes and yawns (more often, with drooping lids, at 20% and below). Charging he peeks out between sips. Full he dozes, stirring now and then for a look round and a yawn
- Settings ▸ Animate Volta turns the idle off. Reduce Motion stills him entirely, and he stops drawing while the display sleeps
- The README's menu-bar screenshots show the current Volta

```

- [ ] **Step 3: Regenerate the README screenshots**

Create `$SCRATCH/shots/main.swift`:

```swift
import AppKit
// The README's menu-bar screenshots: 2×, on the bar colour (38,38,42), 6pt padding, 30pt tall.
let shots: [(String, Int, Bool, Bool, String, BatteryFill, CGFloat)] = [
    ("menubar-discharging", 72, false, false, "5:35", .none, 0),
    ("menubar-low", 15, false, false, "0:48", .red, 0),
    ("menubar-charging", 62, true, true, "1:10", .none, 0),
    ("menubar-full", 100, false, true, "", .none, 0),
    ("menubar-high-power", 80, false, false, "4:10", .blue, 0),
    ("menubar-low-power", 45, false, false, "2:55", .yellow, 0),
    ("menubar-worn", 74, false, false, "3:05", .none, BatteryGlyph.age(health: 60)),
]
let dir = CommandLine.arguments[1]
for s in shots {
    let img = BatteryGlyph.image(pct: s.1, charging: s.2, plugged: s.3, lead: "\(s.1)%", trailing: s.4, ink: .white,
                                 fill: s.5, face: true, sip: s.2 ? 0.3 : nil, age: s.6)
    let W = ceil(img.size.width + 12), H: CGFloat = 30
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * 2), pixelsHigh: Int(H * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(srgbRed: 38/255, green: 38/255, blue: 42/255, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    img.draw(in: NSRect(x: 6, y: (H - img.size.height) / 2, width: img.size.width, height: img.size.height))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(s.0).png"))
}
```

Run:
```bash
mkdir -p $SCRATCH/shots && cd $SCRATCH/shots && cp ~/Code/battery-time-menubar/Sources/BatteryTime/BatteryGlyph.swift . \
  && swiftc -O BatteryGlyph.swift main.swift -o shots 2>&1 | grep error; ./shots ~/Code/battery-time-menubar/screenshots
```

Read all seven PNGs and check each one matches its README row.

- [ ] **Step 4: Regenerate the README glyph images**

First confirm the sibling repos are clean:

```bash
cd ~/Code && for r in keylight-menubar vpn-dns-menubar claude-usage-menubar MacRecorder apollo-monitor-menubar monitor-lizard-menubar home-assistant-menubar soundchain-menubar menu-crane mac-daddy-menubar panes-menubar widgets.nicksmith.software; do d=$(git -C $r status --porcelain | grep -v '^??'); [ -n "$d" ] && echo "DIRTY $r"; done; echo checked
```

Expected: only `checked`. If any repo is dirty, stop and ask Nick.

```bash
bash ~/Code/widgets.nicksmith.software/art/glyphs/render-glyphs.sh >/dev/null 2>&1
cd ~/Code && for r in keylight-menubar vpn-dns-menubar claude-usage-menubar MacRecorder apollo-monitor-menubar monitor-lizard-menubar home-assistant-menubar soundchain-menubar menu-crane mac-daddy-menubar panes-menubar; do [ -n "$(git -C $r status --porcelain)" ] && git -C $r checkout -- . && echo "restored $r"; done
git -C ~/Code/widgets.nicksmith.software status --short
```

Expected: `restored` lines only for repos the render touched for unrelated
reasons (last time: vpn-dns-menubar and apollo-monitor-menubar). The widgets
repo shows only `battery-time` images and, if any app icon changed,
`site/img/mascots/battery-time.png`. Read
`~/Code/battery-time-menubar/docs/menubar-icon.png` and
`docs/animation.png` (in Safari) to check them.

- [ ] **Step 5: Final verification**

Run: `cd ~/Code/battery-time-menubar && swift build -c release 2>&1 | grep -E "error|Build complete"; swift test 2>&1 | grep -E "Suite 'All tests' (passed|failed)|with [1-9][0-9]* failures"`
Expected: `Build complete!` and two `passed` lines.

- [ ] **Step 6: Nick reviews**

Open the review sheet, the animated preview, the seven screenshots and both
README images, then report:
- the frame cost and the CPU numbers, with the power state measured;
- that the site images are regenerated but not committed.

Stop until Nick approves.

- [ ] **Step 7: Release (after approval)**

```bash
cd ~/Code/battery-time-menubar
git add README.md CHANGELOG.md screenshots docs/menubar-icon.png docs/animation.png
git commit -m "1.11.0: Volta's BMO face, and he idles

A smooth digital face in BMO's proportions that glances, blinks, breathes and
yawns on battery, peeks between sips while charging, and dozes when full.
Settings ▸ Animate Volta turns it off; Reduce Motion stills him.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin volta-idle
gh pr create --title "1.11.0: Volta's BMO face, and he idles" --body "Implements docs/superpowers/specs/2026-10-15-volta-bmo-idle-design.md (plan: docs/superpowers/plans/2026-10-15-volta-bmo-idle.md).

- BMO-proportioned face; the 1.10.0 aging re-anchored to it
- IdleDriver (BatteryTimeCore): seeded idle timeline per mood, fully unit-tested
- One animation clock for the idle and sip loop; stops for Reduce Motion, hidden face, display sleep, inactive session
- Settings ▸ Animate Volta
- README screenshots regenerated

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
gh pr checks --watch --interval 10 | grep "release / check"
```

Expected: `release / check pass`. Then:

```bash
gh pr merge --merge && git checkout main && git pull && sleep 30 && git fetch --tags && gh release view v1.11.0 --json tagName -q .tagName
```

Expected: `v1.11.0`.

- [ ] **Step 8: The site (only if Nick approved it)**

```bash
cd ~/Code/widgets.nicksmith.software && git add site/img && git commit -m "Menumon: Volta's BMO face on Battery Time's strip, animation and mascot

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" && npm run deploy 2>&1 | tail -3 && git status --short && git push
```

If `predeploy` left stamp changes in `git status`, commit them as
`Stamp asset versions (predeploy)` and push again.
