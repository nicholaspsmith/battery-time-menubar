// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit

/// Fill colour of the battery glyph. `.none` -> a template image (alpha only,
/// adapts to light/dark); a colour -> a non-template coloured image.
public enum BatteryFill {
    case none, yellow, blue, red
}

/// The menu-bar battery glyph, ported from `render-title.swift`. Composes
/// left-to-right: an optional lead text (e.g. "82%"), the rounded battery body
/// + nub with a fill proportional to charge (bisected by a bolt cutout while
/// charging), then an optional trailing text (e.g. the time). Drawn straight
/// into an NSImage — no PNG/base64 round-trip.
///
/// With a face the battery is Volta: on battery his mouth follows the charge;
/// charging he fills green and drinks through a straw; plugged in but not
/// charging (full, or held at a charge limit) he is stuffed, cheeks puffed,
/// glowing yellow.
public enum BatteryGlyph {
    /// Health (percent) at and above which Volta looks new, and at and below
    /// which he is wrecked. Ten years of daily use leaves a battery around
    /// 40–60%; below 40 it has usually swollen or been replaced.
    static let wornFrom: CGFloat = 92.5, wornOut: CGFloat = 40

    /// How worn a battery at `health` percent looks, 0...1: new down to
    /// `wornFrom`, wrecked at `wornOut`.
    public static func age(health: Double?) -> CGFloat {
        guard let h = health else { return 0 }
        return max(0, min(1, (wornFrom - CGFloat(h)) / (wornFrom - wornOut)))
    }

    /// What Volta's idle (`IdleDriver` in BatteryTimeCore) has him doing, as
    /// drawn here. Its own small type so this file still compiles on its own:
    /// the Menumon site's render-glyphs.sh builds it alone.
    public struct Idle {
        /// −1…1: every face feature shifts 2pt per unit sideways.
        public var gaze: CGFloat
        /// 0…1: a sigh lifts every face feature by up to 0.6pt (0.8pt when full).
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

    public static func image(
        pct: Int,
        charging: Bool,
        plugged: Bool = false,
        lead: String,
        trailing: String,
        ink: NSColor,
        fill fillKind: BatteryFill,
        face: Bool = false,
        sip: CGFloat? = nil,
        slosh: CGFloat? = nil,
        burp: CGFloat? = nil,
        blink: CGFloat? = nil,
        age: CGFloat = 0,
        idle: Idle = .still
    ) -> NSImage {
        // Animation inputs, each nil when still:
        // - sip: 0..<1 through one sip while charging (`sipPeriod`: the charge
        //   climbs his straw, stays while he drinks, and drains back).
        // - slosh: 0...1 through the once-a-minute slosh on battery (the fill
        //   tilts side to side like liquid in a jar, and he grins).
        // - burp: 0...1 through the once-a-minute burp while stuffed.
        // - blink: 0...1 through the once-a-minute blink on battery.
        // Not animated:
        // - age: 0...1, how worn the battery is (`BatteryGlyph.age(health:)`).
        //   He wrinkles, goes grandpa, cracks, leaks and falls apart.
        // - idle: what his idle has him doing (`Idle`); `.still` when off.
        let batteryPct = max(0, min(100, pct))
        let greenFill = face && charging && fillKind == .none
        let drinking = face && charging
        let stuffed = face && plugged && !charging

        // Wear, staged by the health it stands for: each stage comes in over
        // its own band of health and stays as the next arrives.
        let worn = face ? max(0, min(1, age)) : 0
        let health = wornFrom - worn * (wornFrom - wornOut)
        func stage(_ from: CGFloat, _ to: CGFloat) -> CGFloat { max(0, min(1, (from - health) / (from - to))) }
        let wrinkled = stage(wornFrom, 85)  // forehead creases, crow's feet, laugh lines
        let grandpa = stage(85, 75)         // bushy brows, eye bags, heavy lids
        let cracked = stage(75, 65)         // a crack down his casing, then a band-aid on it
        let dripping = stage(65, 55)        // drips of his charge seep from his bottom edge
        let leaking = stage(55, 45)         // a drip lets go and a puddle spreads
        let falling = stage(45, wornOut)    // the crack splits, his terminal swings loose, an ✕ eye
        let fallen = worn >= 1              // his terminal has dropped into the puddle

        // ink = outline / text / % / bolt color; fill = battery-fill color (defaults
        // to ink so a plain mono icon emits as a template that auto-adapts).
        let fill: NSColor = {
            switch fillKind {
            case .yellow: return .systemYellow
            case .blue:   return .systemBlue
            case .red:    return .systemRed
            case .none:   return ink
            }
        }()

        // the % / time text run 2pt smaller than the default menu-bar font
        let font = NSFont.menuBarFont(ofSize: max(1, NSFont.menuBarFont(ofSize: 0).pointSize - 2))
        func attr(_ s: String) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: ink])
        }
        let leadStr = attr(lead), textStr = attr(trailing)
        let leadSize = lead.isEmpty ? NSSize.zero : leadStr.size()
        let textSize = trailing.isEmpty ? NSSize.zero : textStr.size()
        let fontH = ceil(font.ascender - font.descender)

        // battery glyph metrics (points). With a face the battery grows to use
        // more of the 22pt menu-bar height, giving the face room; without one it
        // stays the size of the native battery. The plug keeps the native size.
        let k: CGFloat = face ? 17.0 / 13.0 : 1
        let bodyW: CGFloat = 26 * k, bodyH: CGFloat = 13 * k, nubW: CGFloat = 2 * k, nubH: CGFloat = 5.5 * k
        let radius: CGFloat = 3.2 * k, lineW: CGFloat = 1.2 + (k - 1) * 0.5, fillInset: CGFloat = 1.3 * k, gap: CGFloat = 4
        // The straw pokes out of the top of the battery, drips hang below it,
        // and the glow spreads past its edges, so those take the bar's full
        // height and the glow a little room either side. A terminal swinging
        // loose (or lying in the puddle) needs room to its right.
        let glowPad: CGFloat = stuffed ? 2.5 : 0
        let nubPad: CGFloat = falling > 0 ? 5 : 0
        let glyphW: CGFloat = bodyW + nubW + glowPad * 2 + nubPad
        let leadGap: CGFloat = (!lead.isEmpty && glyphW > 0) ? gap : 0
        let trailGap: CGFloat = (!trailing.isEmpty && (glyphW > 0 || !lead.isEmpty)) ? gap : 0
        let width = max(1, ceil(leadSize.width + leadGap + glyphW + trailGap + textSize.width))
        let height = max(1, ceil(max(fontH, leadSize.height, textSize.height, bodyH, (drinking || stuffed || dripping > 0) ? 22 : 0)))

        func knockout(_ block: () -> Void, clip: NSRect? = nil) {
            NSGraphicsContext.current?.saveGraphicsState()
            if let c = clip { NSBezierPath(rect: c).setClip() }
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            block()
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        // A lightning bolt as a bezier path, centered/scaled into `rect`.
        func boltPath(in rect: NSRect) -> NSBezierPath {
            let pts: [(CGFloat, CGFloat)] = [(0.54,0.92),(0.17,0.42),(0.46,0.42),(0.375,0.083),(0.83,0.625),(0.54,0.625)]
            let xs = pts.map { $0.0 }, ys = pts.map { $0.1 }
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            let sw = rect.width / (maxX - minX), sh = rect.height / (maxY - minY)
            let p = NSBezierPath()
            for (i, pt) in pts.enumerated() {
                let x = rect.minX + (pt.0 - minX) * sw, y = rect.minY + (pt.1 - minY) * sh
                if i == 0 { p.move(to: NSPoint(x: x, y: y)) } else { p.line(to: NSPoint(x: x, y: y)) }
            }
            p.close()
            return p
        }

        func drawBattery(_ pctValue: Int, originX: CGFloat) {
            let by = (height - bodyH) / 2
            let bodyRect = NSRect(x: originX + lineW/2, y: by + lineW/2, width: bodyW - lineW, height: bodyH - lineW)
            let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: radius, yRadius: radius)
            bodyPath.lineWidth = lineW
            let nubRect = NSRect(x: originX + bodyW - lineW, y: (height - nubH)/2, width: nubW, height: nubH)
            var nub = NSBezierPath(roundedRect: nubRect, xRadius: 0.9, yRadius: 0.9)
            if fallen {
                // Dropped off: lying in the puddle under his far corner.
                nub = NSBezierPath(roundedRect: NSRect(x: originX + bodyW - 1, y: 0.3, width: nubH, height: nubW), xRadius: 0.9, yRadius: 0.9)
            } else if falling > 0 {
                // Come loose at the top, swinging down from its bottom corner.
                var t = AffineTransform(translationByX: nubRect.minX, byY: nubRect.minY)
                t.rotate(byDegrees: -50 * falling)
                t.translate(x: -nubRect.minX, y: -nubRect.minY)
                nub.transform(using: t)
            }
            if stuffed {
                // The glow: a soft yellow halo round the outline and terminal.
                NSGraphicsContext.current?.saveGraphicsState()
                let glow = NSShadow()
                glow.shadowColor = NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
                glow.shadowBlurRadius = 3.5
                glow.shadowOffset = .zero
                glow.set()
                // Three times over, so the halo is bright on a light bar as well
                // as a dark one rather than a faint edge.
                for _ in 0..<3 {
                    ink.setStroke(); bodyPath.stroke()
                    ink.setFill(); nub.fill()
                }
                NSGraphicsContext.current?.restoreGraphicsState()
            }
            // Leaking: drips of his charge, in its colour, seep from his bottom
            // edge one after another, the first letting go of its blob as he
            // starts to leak, and a puddle spreads under him (out to his
            // fallen terminal once it drops).
            func drawLeak() {
                (greenFill ? NSColor.systemGreen : fill).setFill()
                let drips: [(x: CGFloat, w: CGFloat, len: CGFloat, from: CGFloat)] =
                    [(0.5, 2.0, 1.9, 0), (0.27, 1.6, 1.5, 0.3), (0.74, 1.5, 1.2, 0.55)]
                let letGo = leaking > 0.33
                for (i, d) in drips.enumerated() {
                    let g = max(0, min(1, (dripping - d.from) / (1 - d.from) * 1.4))
                    guard g > 0 else { continue }
                    drip(x: originX + bodyW * d.x, w: d.w, len: i == 0 && letGo ? 0.35 : d.len * g).fill()
                }
                if letGo {
                    // the blob, mid-fall: a teardrop, point up
                    let x = originX + bodyW * 0.5, r: CGFloat = 0.55, c = NSPoint(x: x, y: 0.95 + r)
                    let drop = NSBezierPath()
                    drop.move(to: NSPoint(x: x, y: by - 0.45))
                    drop.curve(to: NSPoint(x: x - r, y: c.y), controlPoint1: NSPoint(x: x - r * 0.3, y: c.y + r * 1.1),
                               controlPoint2: NSPoint(x: x - r, y: c.y + r * 0.6))
                    drop.appendArc(withCenter: c, radius: r, startAngle: 180, endAngle: 360)
                    drop.curve(to: NSPoint(x: x, y: by - 0.45), controlPoint1: NSPoint(x: x + r, y: c.y + r * 0.6),
                               controlPoint2: NSPoint(x: x + r * 0.3, y: c.y + r * 1.1))
                    drop.fill()
                }
                if leaking > 0 {
                    let l = originX + bodyW * (0.5 - 0.34 * leaking)
                    let r = fallen ? originX + bodyW + nubH : originX + bodyW * (0.5 + 0.3 * leaking)
                    NSBezierPath(ovalIn: NSRect(x: l, y: 0, width: r - l, height: 0.9)).fill()
                }
            }
            // A drip hanging from the bottom edge at `x`: a neck flaring into
            // the outline, a round blob at the end.
            func drip(x: CGFloat, w: CGFloat, len: CGFloat) -> NSBezierPath {
                let top = by + lineW / 2, r = min(w / 2, len * 0.6), f: CGFloat = 0.5
                let c = NSPoint(x: x, y: by - len + r)
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x - r - f, y: top))
                p.curve(to: NSPoint(x: x - r, y: c.y), controlPoint1: NSPoint(x: x - r * 0.7, y: top),
                        controlPoint2: NSPoint(x: x - r, y: (top + c.y) / 2))
                p.appendArc(withCenter: c, radius: r, startAngle: 180, endAngle: 360)
                p.curve(to: NSPoint(x: x + r + f, y: top), controlPoint1: NSPoint(x: x + r, y: (top + c.y) / 2),
                        controlPoint2: NSPoint(x: x + r * 0.7, y: top))
                p.close()
                return p
            }
            ink.setStroke(); bodyPath.stroke()
            drawLeak()
            if fallen {
                // a gap round it, so it reads apart from the puddle it lies in
                knockout({ let gap = nub.copy() as! NSBezierPath; gap.lineWidth = 1.2; gap.stroke() })
            }
            ink.setFill(); nub.fill()
            let innerW = bodyRect.width - 2*fillInset
            let fillRect = NSRect(x: bodyRect.minX + fillInset, y: bodyRect.minY + fillInset,
                                  width: max(0, innerW * CGFloat(pctValue)/100.0), height: bodyRect.height - 2*fillInset)
            let fillShape = NSBezierPath(roundedRect: fillRect, xRadius: 1.3 * k, yRadius: 1.3 * k)
            (greenFill ? NSColor.systemGreen : fill).setFill()
            // While sloshing, the fill's edge is a tilted line, and the face has
            // to split along it rather than along the resting edge.
            var liquidEdge: NSBezierPath?
            if let t = slosh, fillRect.width > 0, fillRect.width < innerW {
                // Liquid in a jar: the fill's edge tilts one way then the other,
                // dying away, pivoting on where it rests.
                let tilt = bodyH * 0.28 * sin(2 * .pi * 1.5 * t) * (1 - t)
                let inner = NSBezierPath(roundedRect: NSRect(x: bodyRect.minX + fillInset, y: fillRect.minY, width: innerW, height: fillRect.height),
                                         xRadius: 1.3 * k, yRadius: 1.3 * k)
                let liquid = NSBezierPath()
                liquid.move(to: NSPoint(x: fillRect.minX - 1, y: fillRect.minY - 1))
                liquid.line(to: NSPoint(x: fillRect.maxX - tilt, y: fillRect.minY - 1))
                liquid.line(to: NSPoint(x: fillRect.maxX + tilt, y: fillRect.maxY + 1))
                liquid.line(to: NSPoint(x: fillRect.minX - 1, y: fillRect.maxY + 1))
                liquid.close()
                liquidEdge = liquid
                NSGraphicsContext.current?.saveGraphicsState()
                inner.addClip(); liquid.fill()
                NSGraphicsContext.current?.restoreGraphicsState()
            } else if let t = sip, greenFill, fillRect.width > 0 {
                // Drinking: the charge is liquid coming in. While the straw is
                // full its edge ripples and bubbles rise through it; as the
                // straw drains they fade and the edge settles flat, and they
                // come back as the next sip climbs.
                let stir = strawFill(t)
                let inner = NSBezierPath(roundedRect: NSRect(x: bodyRect.minX + fillInset, y: fillRect.minY, width: innerW, height: fillRect.height),
                                         xRadius: 1.3 * k, yRadius: 1.3 * k)
                let liquid = NSBezierPath()
                liquid.move(to: NSPoint(x: fillRect.minX - 1, y: fillRect.minY - 1))
                let steps = 8
                for i in 0...steps {
                    let f = CGFloat(i) / CGFloat(steps)
                    let wave = fillRect.width < innerW ? 0.7 * stir * sin(2 * .pi * (f * 1.2 - t * 6)) : 0
                    liquid.line(to: NSPoint(x: fillRect.maxX + wave, y: fillRect.minY + f * fillRect.height))
                }
                liquid.line(to: NSPoint(x: fillRect.minX - 1, y: fillRect.maxY + 1))
                liquid.close()
                liquidEdge = liquid
                NSGraphicsContext.current?.saveGraphicsState()
                inner.addClip(); liquid.addClip()
                liquid.fill()
                NSColor.white.withAlphaComponent(0.6 * stir).setFill()
                let bubbles: [(x: CGFloat, phase: CGFloat, r: CGFloat)] = [(0.12, 0.0, 0.55), (0.3, 0.55, 0.75), (0.68, 0.25, 0.6), (0.86, 0.75, 0.7)]
                for b in bubbles {
                    let u = (t * 3 + b.phase).truncatingRemainder(dividingBy: 1)
                    let x = fillRect.minX + fillRect.width * b.x + 0.4 * sin(2 * .pi * u * 2)
                    let y = fillRect.minY + u * (fillRect.height + 2) - 1
                    NSBezierPath(ovalIn: NSRect(x: x - b.r, y: y - b.r, width: b.r * 2, height: b.r * 2)).fill()
                }
                NSGraphicsContext.current?.restoreGraphicsState()
            } else {
                fillShape.fill()
            }

            let cx = originX + bodyW/2, cy = height/2

            // Cracked: a crack runs down from his top edge, further the more
            // cracked he is, and gets a band-aid slapped across it; once he
            // falls apart it runs right through and gapes. Knocked through
            // the casing and charge here; the face pass inks it over the
            // empty part.
            var crack: NSBezierPath?
            var bandAid: NSBezierPath?
            if cracked > 0 {
                let x = originX + bodyW * 0.14
                // It ends under the band-aid until the patch gives way.
                let aidAt = NSPoint(x: x + 0.3, y: cy - bodyH * 0.12)
                var pts = [NSPoint(x: x + 0.4, y: by + bodyH + 0.5),
                           NSPoint(x: x - 0.8, y: cy + bodyH * 0.24),
                           NSPoint(x: x + 0.8, y: cy + bodyH * 0.06),
                           aidAt]
                if falling > 0 { pts += [NSPoint(x: x - 0.7, y: cy - bodyH * 0.3), NSPoint(x: x - 0.1, y: by - 0.5)] }
                let c = polyline(pts, upTo: cracked)
                c.lineWidth = 0.6 + 0.25 * cracked + 0.9 * falling
                crack = c
                if cracked > 0.7 {
                    // two strips crossed in an ✕, cartoon style
                    let w = bodyH * 0.46, h = bodyH * 0.1
                    let aid = NSBezierPath()
                    for angle in [35.0, -35.0] as [CGFloat] {
                        var t = AffineTransform(translationByX: aidAt.x, byY: aidAt.y)
                        t.rotate(byDegrees: angle)
                        let strip = NSBezierPath(roundedRect: NSRect(x: -w / 2, y: -h / 2, width: w, height: h), xRadius: h / 2, yRadius: h / 2)
                        strip.transform(using: t)
                        aid.append(strip)
                    }
                    bandAid = aid
                }
                knockout({ c.stroke() })
            }

            if face {
                // Volta's face. On battery his mouth follows the charge — a smile
                // when full, a flat line around half, a frown when low. Charging
                // he drinks through a straw with happy closed eyes; plugged in
                // but not charging he is stuffed: contented closed eyes and
                // puffed cheeks.
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
                        if lid > 0 {
                            // a dot cut flat across the top, squashed as he
                            // blinks (never taller than the lid allows)
                            let r = eye / 2
                            let th = asin(max(-1, min(1, (r - lid * eye) / r))) * 180 / .pi
                            let e = NSBezierPath()
                            e.appendArc(withCenter: .zero, radius: r, startAngle: th, endAngle: 180 - th, clockwise: true)
                            e.close()
                            var t = AffineTransform(translationByX: ex, byY: eyeY + r)
                            t.scale(x: eyeW / eye, y: max(0.23, 1 - shut))
                            e.transform(using: t)
                            fills.append(e)
                        } else {
                            fills.append(NSBezierPath(ovalIn: NSRect(x: ex - eyeW / 2, y: eyeY + (eye - h) / 2,
                                                                     width: eyeW, height: max(0.6, h))))
                        }
                    }
                }

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

                // Age lines: forehead creases between the eyes, crow's feet at
                // their outer corners, and laugh lines beside the mouth, each
                // appearing in turn and growing longer and bolder with age.
                if wrinkled > 0 {
                    let lw = 0.35 + 0.45 * wrinkled
                    func line(_ pts: [NSPoint]) {
                        let l = NSBezierPath()
                        l.move(to: pts[0])
                        if pts.count == 3 { l.curve(to: pts[2], controlPoint1: pts[1], controlPoint2: pts[1]) }
                        else { pts.dropFirst().forEach { l.line(to: $0) } }
                        l.lineWidth = lw; l.lineCapStyle = .round
                        strokes.append(l)
                    }
                    // How far along (0...1) a feature that starts at `from` is.
                    func grown(_ from: CGFloat) -> CGFloat { max(0, min(1, (wrinkled - from) / (1 - from) * 1.5)) }
                    let foreheadYs = [cy + bodyH * 0.31, cy + bodyH * 0.23]
                    for (i, y) in foreheadYs.enumerated() {
                        let g = grown(CGFloat(i) * 0.35)
                        guard g > 0 else { continue }
                        let half = bodyW * 0.1 * (0.4 + 0.6 * g)
                        line([NSPoint(x: cx - half, y: y), NSPoint(x: cx, y: y + bodyH * 0.025), NSPoint(x: cx + half, y: y)])
                    }
                    let crow = grown(0.15)
                    if crow > 0 {
                        for side in [-1.0, 1.0] as [CGFloat] {
                            let x0 = cx + side * (eyeOffset + eye * 0.95)
                            let len = bodyH * 0.11 * (0.4 + 0.6 * crow)
                            line([NSPoint(x: x0, y: eyeY + eye * 0.75), NSPoint(x: x0 + side * len, y: eyeY + eye * 0.75 + len * 0.45)])
                            if crow > 0.5 {
                                line([NSPoint(x: x0, y: eyeY + eye * 0.25), NSPoint(x: x0 + side * len, y: eyeY + eye * 0.25 - len * 0.45)])
                            }
                        }
                    }
                    let laugh = grown(0.5)
                    if laugh > 0 {
                        for side in [-1.0, 1.0] as [CGFloat] {
                            let x0 = cx + side * (mouthHalfW + bodyH * 0.065)
                            let top = mouthY + bodyH * 0.08, len = bodyH * 0.16 * (0.4 + 0.6 * laugh)
                            line([NSPoint(x: x0, y: top), NSPoint(x: x0 + side * bodyH * 0.06, y: top - len * 0.5),
                                  NSPoint(x: x0 + side * bodyH * 0.02, y: top - len)])
                        }
                    }
                }
                if grandpa > 0 {
                    // Grandpa's bushy brows, tilted down at the outside, filling
                    // out as he ages, and bags under his eyes.
                    for ex in eyeXs {
                        let side: CGFloat = ex < cx ? -1 : 1
                        let y = eyeY + eye * 1.6
                        let b = NSBezierPath()
                        b.move(to: NSPoint(x: ex - side * eye * 0.45, y: y + eye * 0.1))
                        b.line(to: NSPoint(x: ex + side * eye * (0.3 + 0.5 * grandpa), y: y - eye * 0.15))
                        b.lineWidth = max(0.7, bodyH * 0.07 * (0.6 + 0.4 * grandpa)); b.lineCapStyle = .round
                        strokes.append(b)
                        if grandpa > 0.3 {
                            let bag = NSBezierPath()
                            bag.appendArc(withCenter: NSPoint(x: ex, y: eyeY + eye * 0.2), radius: eye * 0.7, startAngle: 215, endAngle: 325)
                            bag.lineWidth = 0.5; bag.lineCapStyle = .round
                            strokes.append(bag)
                        }
                    }
                }

                // The idle turns his face (gaze) and lifts it as he sighs.
                // The casing's crack, band-aid and drips stay put.
                let faceDX = idle.gaze * 2, faceDY = idle.breath * (stuffed ? 0.8 : 0.6)
                if faceDX != 0 || faceDY != 0 {
                    let t = AffineTransform(translationByX: faceDX, byY: faceDY)
                    for p in fills + strokes { p.transform(using: t) }
                }

                let draw = {
                    for f in fills { f.fill() }
                    for st in strokes { st.stroke() }
                    crack?.stroke()
                    bandAid?.fill()
                }
                // The face straddles the fill's edge, so it is split there. Over a
                // yellow fill it is black (a knocked-out hole shows the bar, which
                // is too light to read on yellow in light mode); over any other
                // fill it is knocked out (reads as a hole in the charge). Over the
                // empty part it is drawn in ink (a hole in nothing is invisible).
                let split = fillRect.maxX
                let filled = NSRect(x: bodyRect.minX, y: bodyRect.minY, width: max(0, split - bodyRect.minX), height: bodyRect.height)
                let empty = NSRect(x: split, y: bodyRect.minY, width: max(0, bodyRect.maxX - split), height: bodyRect.height)
                if let liquid = liquidEdge {
                    NSGraphicsContext.current?.saveGraphicsState()
                    liquid.addClip()
                    NSGraphicsContext.current?.compositingOperation = .destinationOut
                    draw()
                    NSGraphicsContext.current?.restoreGraphicsState()
                    NSGraphicsContext.current?.saveGraphicsState()
                    let outside = NSBezierPath(rect: bodyRect)
                    outside.append(liquid)
                    outside.windingRule = .evenOdd
                    outside.addClip()
                    ink.set(); draw()
                    NSGraphicsContext.current?.restoreGraphicsState()
                } else if filled.width > 0 {
                    if fillKind == .yellow {
                        NSGraphicsContext.current?.saveGraphicsState()
                        NSBezierPath(rect: filled).setClip()
                        NSColor.black.set(); draw()
                        NSGraphicsContext.current?.restoreGraphicsState()
                    } else {
                        knockout(draw, clip: filled)
                    }
                }
                if liquidEdge == nil, empty.width > 0 {
                    NSGraphicsContext.current?.saveGraphicsState()
                    NSBezierPath(rect: empty).setClip()
                    ink.set(); draw()
                    NSGraphicsContext.current?.restoreGraphicsState()
                }

                if drinking {
                    drawStraw(mouth: NSPoint(x: cx + faceDX, y: mouthY + faceDY), bodyH: bodyH, sip: sip)
                }
                if stuffed, let b = burp, b > 0.25, b < 0.95 {
                    // The burp: a little bubble rising from his mouth and popping.
                    let u = (b - 0.25) / 0.7
                    let r = bodyH * (0.07 + 0.06 * u)
                    let at = NSPoint(x: cx + faceDX + bodyW * 0.08 + u * bodyW * 0.12, y: mouthY + faceDY + u * bodyH * 0.45)
                    let bubble = NSBezierPath(ovalIn: NSRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
                    bubble.lineWidth = 0.7
                    ink.withAlphaComponent(1 - u * 0.6).setStroke(); bubble.stroke()
                }
            } else if charging {
                // a bolt bisecting the glyph like the native charging icon: a CUTOUT
                // finished with a crisp ink border so it stays defined over both the
                // filled and empty parts of the body.
                let boltH = bodyH - 1.5, boltW = boltH * 0.79
                let r = NSRect(x: cx - boltW/2, y: cy - boltH/2, width: boltW, height: boltH)
                let path = boltPath(in: r)
                knockout({ path.fill() })
                path.lineWidth = 1.0; ink.setStroke(); path.stroke()
            }
        }

        let img = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            if !lead.isEmpty {
                leadStr.draw(at: NSPoint(x: x, y: (height - leadSize.height)/2))
                x += leadSize.width + leadGap
            }
            drawBattery(batteryPct, originX: x + glowPad)
            x += glyphW + trailGap
            if !trailing.isEmpty {
                textStr.draw(at: NSPoint(x: x, y: (height - textSize.height)/2))
            }
            return true
        }

        // the green charging fill, the straw and the glow need colour, so
        // those are never templates
        img.isTemplate = (fillKind == .none) && !greenFill && !stuffed
        return img
    }

    /// One sip, in seconds: the charge climbs the straw (1.2 s), the straw
    /// stays full while he drinks (5 s), it drains back down (1.2 s), and he
    /// pauses (0.5 s) before the next.
    public static let sipPeriod: TimeInterval = 7.9
    private static let sipRise = 1.2 / 7.9, sipHold = 5.0 / 7.9, sipFall = 1.2 / 7.9

    /// How full the straw is (0...1) at `t` through a sip.
    static func strawFill(_ t: CGFloat) -> CGFloat {
        if t < sipRise { return ease(t / sipRise) }
        if t < sipRise + sipHold { return 1 }
        if t < sipRise + sipHold + sipFall { return 1 - ease((t - sipRise - sipHold) / sipFall) }
        return 0
    }

    /// His lips swelling as he swallows: four gulps while the straw is full.
    static func gulp(_ t: CGFloat) -> CGFloat {
        guard t >= sipRise, t < sipRise + sipHold else { return 0 }
        let u = (t - sipRise) / sipHold
        return 0.5 - 0.5 * cos(2 * .pi * u * 4)
    }

    /// The first `f` (0...1) of the polyline through `pts`, by length.
    private static func polyline(_ pts: [NSPoint], upTo f: CGFloat) -> NSBezierPath {
        let lens = zip(pts, pts.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var left = lens.reduce(0, +) * max(0, min(1, f))
        let p = NSBezierPath()
        p.move(to: pts[0])
        for (i, len) in lens.enumerated() {
            let a = pts[i], b = pts[i + 1]
            if left >= len { p.line(to: b); left -= len; continue }
            let u = left / len
            p.line(to: NSPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u))
            break
        }
        return p
    }

    /// Smoothstep 0...1.
    private static func ease(_ u: CGFloat) -> CGFloat { let v = max(0, min(1, u)); return v * v * (3 - 2 * v) }

    /// Volta drinking green charge through a red bendy straw (outlined in its
    /// own darker red, ridged below the bend, with a see-through core) that
    /// rises from below the bar, the drink out of sight. Each sip the charge
    /// climbs the straw, stays while he drinks, and drains back.
    private static func drawStraw(mouth: NSPoint, bodyH: CGFloat, sip: CGFloat?) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Still (no animation): the straw full, mid-drink.
        let climb = sip.map(strawFill) ?? 1

        // The straw, shaped like a 7: a long stem up from below the bar, then
        // a short bend over into his mouth.
        let w: CGFloat = 2.6, rim: CGFloat = 0.42
        let tip = CGPoint(x: mouth.x + bodyH * 0.06, y: mouth.y + bodyH * 0.01)
        let foot = CGPoint(x: tip.x + bodyH * 0.27, y: 0)
        let bend = CGPoint(x: foot.x, y: mouth.y + bodyH * 0.09)
        let straw = CGMutablePath()
        straw.move(to: foot); straw.addLine(to: bend); straw.addLine(to: tip)
        let red = NSColor(srgbRed: 1, green: 0.3, blue: 0.4, alpha: 1).cgColor
        let darkRed = NSColor(srgbRed: 0.62, green: 0.08, blue: 0.18, alpha: 1).cgColor

        // Straw outline, body, see-through core and the climbing charge.
        let outer = straw.copy(strokingWithWidth: w, lineCap: .butt, lineJoin: .round, miterLimit: 4)
        let inner = straw.copy(strokingWithWidth: w - rim * 2, lineCap: .butt, lineJoin: .round, miterLimit: 4)
        let core = straw.copy(strokingWithWidth: w - rim * 2 - 0.45, lineCap: .butt, lineJoin: .round, miterLimit: 4)
        ctx.saveGState()
        ctx.addPath(outer); ctx.setFillColor(darkRed); ctx.fillPath()
        ctx.addPath(inner); ctx.setFillColor(red); ctx.fillPath()
        ctx.addPath(core); ctx.setFillColor(NSColor(srgbRed: 1, green: 0.78, blue: 0.82, alpha: 1).cgColor); ctx.fillPath()
        let up = bend.y - foot.y, over = hypot(tip.x - bend.x, tip.y - bend.y)
        let head = climb * (up + over)
        let column = CGMutablePath()
        column.move(to: foot)
        if head <= up { column.addLine(to: CGPoint(x: foot.x, y: foot.y + head)) }
        else {
            column.addLine(to: bend)
            let f = (head - up) / over
            column.addLine(to: CGPoint(x: bend.x + (tip.x - bend.x) * f, y: bend.y + (tip.y - bend.y) * f))
        }
        ctx.addPath(core); ctx.clip()
        ctx.addPath(column.copy(strokingWithWidth: w, lineCap: .butt, lineJoin: .round, miterLimit: 4))
        ctx.setFillColor(NSColor.systemGreen.cgColor); ctx.fillPath()
        ctx.restoreGState()
        // Ridges on the stem just below the bend.
        ctx.saveGState(); ctx.addPath(outer); ctx.clip()
        ctx.clip(to: CGRect(x: bend.x - w / 2, y: 0, width: w, height: bend.y))
        ctx.setStrokeColor(darkRed); ctx.setLineWidth(0.35)
        for k in 0..<3 {
            let y = bend.y - w / 2 - 0.4 - CGFloat(k) * 0.7
            ctx.move(to: CGPoint(x: bend.x - w, y: y)); ctx.addLine(to: CGPoint(x: bend.x + w, y: y))
        }
        ctx.strokePath(); ctx.restoreGState()
    }
}
