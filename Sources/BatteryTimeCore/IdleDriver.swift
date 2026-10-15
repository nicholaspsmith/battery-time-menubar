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
    /// 0…1: a sigh lifting his face.
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

/// Volta's idle: glances, blinks, yawns, sighs, peeks and stirs on a seeded
/// random timeline, so it varies but a test can replay it exactly. Time is
/// any monotonic clock in seconds. Each gesture is scheduled when the
/// previous one of its kind ends, at a random interval for its kind. Between
/// gestures nothing moves, so nothing needs drawing: every menu-bar redraw
/// costs macOS ~5 ms of CPU, and on battery he should average about one.
public struct IdleDriver {
    /// Redraw intervals: while something moves, while only a (slow) sigh
    /// moves, the shortest the menu bar is ever asked for, and the longest
    /// he waits before checking in.
    public static let movingTick: TimeInterval = 1.0 / 10
    public static let sighTick: TimeInterval = 1.0 / 4
    public static let minimumTick: TimeInterval = 1.0 / 60
    public static let longestTick: TimeInterval = 60

    static let moodEase: TimeInterval = 0.3
    static let cueEase: TimeInterval = 0.2

    enum Kind: CaseIterable { case glance, blink, yawn, sigh, peek, stir }

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
    private var cuePlaying = false
    private var cueChanged = -TimeInterval.infinity
    private var moodChanged = -TimeInterval.infinity
    private var moodFrom = IdlePose()
    private var last: TimeInterval

    public init(seed: UInt64, mood: IdleMood, at t: TimeInterval) {
        rng = SplitMix64(seed: seed)
        self.mood = mood
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
        for g in active where g.start <= t && t < g.end { apply(g, at: t - g.start, to: &p) }
        let c = cueMask(at: t)
        if c > 0 { p.gaze *= 1 - c; p.peek *= 1 - c; p.yawn *= 1 - c; p.blink *= 1 - c }
        let m = t - moodChanged
        if m < Self.moodEase { p = .mix(moodFrom, p, Self.ease(m / Self.moodEase)) }
        return p
    }

    /// Seconds from `t` until the pose next needs drawing: `movingTick` while
    /// anything ramps, `sighTick` while only a sigh moves, and through a still
    /// stretch (a hold, or rest between gestures) one frame into the next
    /// movement, since its first instant looks like the frame before. At most
    /// `longestTick`.
    public mutating func nextTick(after t: TimeInterval) -> TimeInterval {
        advance(to: t)
        if t - moodChanged < Self.moodEase || t - cueChanged < Self.cueEase { return Self.movingTick }
        var wait = Self.longestTick
        for g in active where g.start <= t && t < g.end {
            let frame = g.kind == .sigh ? Self.sighTick : Self.movingTick
            if let still = stillUntil(g, at: t - g.start) { wait = min(wait, still - t + frame) }
            else { wait = min(wait, frame) }
        }
        if !cuePlaying {
            for k in Self.kinds(for: mood) {
                if let n = next[k] { wait = min(wait, n - t + (k == .sigh ? Self.sighTick : Self.movingTick)) }
            }
        }
        return max(wait, Self.minimumTick)
    }

    // MARK: Timeline

    private static func kinds(for mood: IdleMood) -> [Kind] {
        switch mood {
        case .awake: return [.glance, .blink, .yawn, .sigh]
        case .drinking: return [.peek, .sigh]
        case .sleepy: return [.stir, .sigh]
        }
    }

    private mutating func schedule(from t: TimeInterval) {
        next = [:]
        for k in Self.kinds(for: mood) { next[k] = t + interval(k) }
    }

    private mutating func interval(_ k: Kind) -> TimeInterval {
        switch k {
        case .glance: return rng.uniform(10, 20)
        case .blink: return rng.uniform(5, 9)
        case .yawn: return mood == .awake(tired: true) ? rng.uniform(45, 90) : rng.uniform(120, 240)
        case .sigh:
            switch mood {
            case .awake: return rng.uniform(40, 70)
            case .drinking: return rng.uniform(20, 40)
            case .sleepy: return rng.uniform(15, 30)
            }
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
        case .sigh:
            return Gesture(kind: k, start: s, length: mood == .sleepy ? 4 : 3, side: 0, hold: 0, double: false)
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
        case .sigh:
            p.breath = Self.sigh(u, length: g.length)
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

    /// While a gesture holds still, when it moves again (absolute time); nil
    /// while it moves. A stir's settle looks like rest, so it never moves again.
    private func stillUntil(_ g: Gesture, at u: TimeInterval) -> TimeInterval? {
        func hold(_ from: TimeInterval, _ to: TimeInterval) -> TimeInterval? { u >= from && u < to ? g.start + to : nil }
        switch g.kind {
        case .glance: return hold(0.25, 0.25 + g.hold)
        case .blink: return nil
        case .yawn: return hold(0.6, 1.8)
        case .sigh: return hold(0.4 * g.length, 0.5 * g.length)
        case .peek: return hold(0.45, 1.15)
        case .stir: return u >= 5.0 ? .infinity : hold(0.65, 1.35) ?? hold(2.2, 3.4)
        }
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

    /// One sigh: breathe in over 40% of it, hold 10%, breathe out over 50%.
    static func sigh(_ u: TimeInterval, length: TimeInterval) -> Double {
        let f = u / length
        if f < 0 || f >= 1 { return 0 }
        if f < 0.4 { return ease(f / 0.4) }
        if f < 0.5 { return 1 }
        return 1 - ease((f - 0.5) / 0.5)
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
