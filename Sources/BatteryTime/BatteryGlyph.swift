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
    /// How worn a battery at `health` percent looks: new at 100, a grandpa
    /// from 80 down.
    public static func age(health: Int?) -> CGFloat {
        guard let h = health else { return 0 }
        return max(0, min(1, CGFloat(100 - h) / 20))
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
        age: CGFloat = 0
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
        //   Wrinkles deepen with it; at 1 he is a grandpa, bushy brows and all.
        let batteryPct = max(0, min(100, pct))
        let greenFill = face && charging && fillKind == .none
        let drinking = face && charging
        let stuffed = face && plugged && !charging

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
        // The straw pokes out of the top of the battery, and the glow spreads
        // past its edges, so both states take the bar's full height and the
        // glow a little room either side.
        let glowPad: CGFloat = stuffed ? 2.5 : 0
        let glyphW: CGFloat = bodyW + nubW + glowPad * 2
        let leadGap: CGFloat = (!lead.isEmpty && glyphW > 0) ? gap : 0
        let trailGap: CGFloat = (!trailing.isEmpty && (glyphW > 0 || !lead.isEmpty)) ? gap : 0
        let width = max(1, ceil(leadSize.width + leadGap + glyphW + trailGap + textSize.width))
        let height = max(1, ceil(max(fontH, leadSize.height, textSize.height, bodyH, (drinking || stuffed) ? 22 : 0)))

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
            let nub = NSBezierPath(roundedRect: NSRect(x: originX + bodyW - lineW, y: (height - nubH)/2, width: nubW, height: nubH), xRadius: 0.9, yRadius: 0.9)
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
            ink.setStroke(); bodyPath.stroke()
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
                // Drinking: the charge is liquid coming in. Its edge ripples and
                // bubbles rise through it, three times a sip.
                let inner = NSBezierPath(roundedRect: NSRect(x: bodyRect.minX + fillInset, y: fillRect.minY, width: innerW, height: fillRect.height),
                                         xRadius: 1.3 * k, yRadius: 1.3 * k)
                let liquid = NSBezierPath()
                liquid.move(to: NSPoint(x: fillRect.minX - 1, y: fillRect.minY - 1))
                let steps = 8
                for i in 0...steps {
                    let f = CGFloat(i) / CGFloat(steps)
                    let wave = fillRect.width < innerW ? 0.7 * sin(2 * .pi * (f * 1.2 - t * 6)) : 0
                    liquid.line(to: NSPoint(x: fillRect.maxX + wave, y: fillRect.minY + f * fillRect.height))
                }
                liquid.line(to: NSPoint(x: fillRect.minX - 1, y: fillRect.maxY + 1))
                liquid.close()
                liquidEdge = liquid
                NSGraphicsContext.current?.saveGraphicsState()
                inner.addClip(); liquid.addClip()
                liquid.fill()
                NSColor.white.withAlphaComponent(0.6).setFill()
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
            if face {
                // Volta's face. On battery his mouth follows the charge — a smile
                // when full, a flat line around half, a frown when low. Charging
                // he drinks through a straw with happy closed eyes; plugged in
                // but not charging he is stuffed: contented closed eyes and
                // puffed cheeks.
                let eye = bodyH * 0.15
                let low = fillKind == .red
                let eyeY = cy + bodyH * 0.08
                let eyeXs = [cx - bodyW * 0.17, cx + bodyW * 0.17]
                let mouthLW = max(0.9, bodyH * 0.08)
                // Shapes knocked out of (or inked over) the fill, and anything
                // drawn on top afterwards in its own colours.
                var strokes: [NSBezierPath] = []
                var fills: [NSBezierPath] = []

                // A once-a-minute blink closes the eyes for the middle of `blink`.
                let shut: CGFloat = {
                    guard let b = blink else { return 0 }
                    return b < 0.35 ? b / 0.35 : b < 0.5 ? 1 : max(0, 1 - (b - 0.5) / 0.4)
                }()

                if drinking {
                    for ex in eyeXs {                                  // happy ^ ^
                        let e = NSBezierPath()
                        e.move(to: NSPoint(x: ex - eye * 0.8, y: eyeY + eye * 0.2))
                        e.line(to: NSPoint(x: ex, y: eyeY + eye * 1.0))
                        e.line(to: NSPoint(x: ex + eye * 0.8, y: eyeY + eye * 0.2))
                        e.lineWidth = mouthLW; e.lineCapStyle = .round; e.lineJoinStyle = .round
                        strokes.append(e)
                    }
                } else if stuffed {
                    for ex in eyeXs {                                  // contented ‿ ‿
                        let e = NSBezierPath()
                        e.appendArc(withCenter: NSPoint(x: ex, y: eyeY + eye * 0.9), radius: eye * 0.75,
                                    startAngle: 200, endAngle: 340, clockwise: false)
                        e.lineWidth = mouthLW; e.lineCapStyle = .round
                        strokes.append(e)
                    }
                } else if shut > 0.85 {
                    for ex in eyeXs {                                  // mid-blink: a line
                        let e = NSBezierPath()
                        e.move(to: NSPoint(x: ex - eye * 0.6, y: eyeY + eye / 2))
                        e.line(to: NSPoint(x: ex + eye * 0.6, y: eyeY + eye / 2))
                        e.lineWidth = mouthLW; e.lineCapStyle = .round
                        strokes.append(e)
                    }
                } else {
                    let h = eye * (1 - shut)
                    for ex in eyeXs {
                        fills.append(NSBezierPath(ovalIn: NSRect(x: ex - eye/2, y: eyeY + (eye - h) / 2, width: eye, height: max(0.6, h))))
                    }
                }

                let mouthY = cy - bodyH * 0.12
                if drinking {
                    // Lips pursed round the straw, swelling a touch as each sip
                    // arrives.
                    let gulp: CGFloat = sip.map(gulp) ?? 0
                    let r = bodyH * (0.085 + 0.035 * gulp)
                    fills.append(NSBezierPath(ovalIn: NSRect(x: cx - r, y: mouthY - r, width: r * 2, height: r * 2)))
                } else if stuffed {
                    // A small closed mouth. The burp opens it for a moment.
                    let b = burp ?? 0
                    let burping = b > 0.2 && b < 0.75
                    if burping {
                        let r = bodyH * 0.07
                        fills.append(NSBezierPath(ovalIn: NSRect(x: cx - r, y: mouthY - r, width: r * 2, height: r * 2)))
                    } else {
                        let m = NSBezierPath()
                        m.move(to: NSPoint(x: cx - bodyH * 0.06, y: mouthY)); m.line(to: NSPoint(x: cx + bodyH * 0.06, y: mouthY))
                        m.lineWidth = mouthLW; m.lineCapStyle = .round
                        strokes.append(m)
                    }
                } else {
                    let mouth = NSBezierPath()
                    let halfW = bodyH * 0.17
                    if slosh != nil {
                        // A grin while his charge sloshes about.
                        mouth.appendArc(withCenter: NSPoint(x: cx, y: cy - bodyH * 0.06), radius: bodyH * 0.2, startAngle: 180, endAngle: 360, clockwise: false)
                        mouth.close()
                        fills.append(mouth)
                    } else {
                        if low {
                            mouth.appendArc(withCenter: NSPoint(x: cx, y: cy - bodyH * 0.34), radius: bodyH * 0.2, startAngle: 35, endAngle: 145, clockwise: false)
                        } else {
                            // a smile from 60%, flat from 35%, a slight frown below
                            let sag: CGFloat = pctValue >= 60 ? bodyH * 0.085 : pctValue >= 35 ? 0 : -bodyH * 0.04
                            let endY = cy - bodyH * 0.1 - (bodyH * 0.085 - sag) / 2
                            mouth.move(to: NSPoint(x: cx - halfW, y: endY))
                            mouth.curve(to: NSPoint(x: cx + halfW, y: endY),
                                        controlPoint1: NSPoint(x: cx - halfW * 0.5, y: endY - sag * 1.33),
                                        controlPoint2: NSPoint(x: cx + halfW * 0.5, y: endY - sag * 1.33))
                        }
                        mouth.lineWidth = mouthLW; mouth.lineCapStyle = .round
                        strokes.append(mouth)
                    }
                }

                // Age lines: forehead creases between the eyes, crow's feet at
                // their outer corners, and laugh lines beside the mouth, each
                // appearing in turn and growing longer and bolder with age.
                let a = max(0, min(1, age))
                if a > 0 {
                    let lw = 0.35 + 0.45 * a
                    func line(_ pts: [NSPoint]) {
                        let l = NSBezierPath()
                        l.move(to: pts[0])
                        if pts.count == 3 { l.curve(to: pts[2], controlPoint1: pts[1], controlPoint2: pts[1]) }
                        else { pts.dropFirst().forEach { l.line(to: $0) } }
                        l.lineWidth = lw; l.lineCapStyle = .round
                        strokes.append(l)
                    }
                    // How far along (0...1) a feature that starts at `from` is.
                    func grown(_ from: CGFloat) -> CGFloat { max(0, min(1, (a - from) / (1 - from) * 1.5)) }
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
                            let x0 = cx + side * (bodyW * 0.17 + eye * 0.95)
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
                            let x0 = cx + side * bodyH * 0.3
                            let top = mouthY + bodyH * 0.08, len = bodyH * 0.16 * (0.4 + 0.6 * laugh)
                            line([NSPoint(x: x0, y: top), NSPoint(x: x0 + side * bodyH * 0.06, y: top - len * 0.5),
                                  NSPoint(x: x0 + side * bodyH * 0.02, y: top - len)])
                        }
                    }
                    if a >= 1 {
                        // Grandpa's bushy brows, tilted down at the outside.
                        for ex in eyeXs {
                            let side: CGFloat = ex < cx ? -1 : 1
                            let y = eyeY + eye * 1.6
                            let b = NSBezierPath()
                            b.move(to: NSPoint(x: ex - side * eye * 0.45, y: y + eye * 0.1))
                            b.line(to: NSPoint(x: ex + side * eye * 0.8, y: y - eye * 0.15))
                            b.lineWidth = max(1, bodyH * 0.07); b.lineCapStyle = .round
                            strokes.append(b)
                        }
                    }
                }

                let draw = {
                    for f in fills { f.fill() }
                    for st in strokes { st.stroke() }
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
                    drawStraw(mouth: NSPoint(x: cx, y: mouthY), bodyW: bodyW, bodyH: bodyH, sip: sip)
                }
                if stuffed, let b = burp, b > 0.25, b < 0.95 {
                    // The burp: a little bubble rising from his mouth and popping.
                    let u = (b - 0.25) / 0.7
                    let r = bodyH * (0.07 + 0.06 * u)
                    let at = NSPoint(x: cx + bodyW * 0.08 + u * bodyW * 0.12, y: mouthY + u * bodyH * 0.45)
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

    /// Smoothstep 0...1.
    private static func ease(_ u: CGFloat) -> CGFloat { let v = max(0, min(1, u)); return v * v * (3 - 2 * v) }

    /// Volta drinking through a straw from a big cup of green charge: only the
    /// cup's top shows, rising from below the bar in front of him, and a red
    /// bendy straw (outlined in its own darker red, ridged at the bend, with
    /// a see-through core) runs from the drink to his mouth. Each sip the
    /// charge climbs the straw, stays while he drinks, and drains back.
    private static func drawStraw(mouth: NSPoint, bodyW: CGFloat, bodyH: CGFloat, sip: CGFloat?) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Still (no animation): the straw full, mid-drink.
        let climb = sip.map(strawFill) ?? 1

        // The glass: a tumbler, a little wider at the rim.
        // Only the top of a big cup shows: it rises from below the bar, so
        // its rim is all you see of it.
        let cupW: CGFloat = bodyH * 0.95, cupH: CGFloat = bodyH * 1.1
        let cupX = mouth.x + bodyW * 0.235, cupY: CGFloat = -bodyH * 0.62
        let taper = cupW * 0.1
        let glass = CGMutablePath()
        glass.move(to: CGPoint(x: cupX - cupW / 2 + taper, y: cupY))
        glass.addLine(to: CGPoint(x: cupX + cupW / 2 - taper, y: cupY))
        glass.addLine(to: CGPoint(x: cupX + cupW / 2, y: cupY + cupH))
        glass.addLine(to: CGPoint(x: cupX - cupW / 2, y: cupY + cupH))
        glass.closeSubpath()
        let edge = NSColor(srgbRed: 0.42, green: 0.48, blue: 0.55, alpha: 1).cgColor

        // The straw: up out of the glass, bent over, down into his mouth.
        let w: CGFloat = 2.6, rim: CGFloat = 0.42
        let foot = CGPoint(x: cupX + cupW * 0.24, y: 0)
        let bend = CGPoint(x: foot.x, y: mouth.y + bodyH * 0.09)
        let tip = CGPoint(x: mouth.x + bodyH * 0.06, y: mouth.y + bodyH * 0.01)
        let straw = CGMutablePath()
        straw.move(to: foot); straw.addLine(to: bend); straw.addLine(to: tip)
        let red = NSColor(srgbRed: 1, green: 0.3, blue: 0.4, alpha: 1).cgColor
        let darkRed = NSColor(srgbRed: 0.62, green: 0.08, blue: 0.18, alpha: 1).cgColor

        // Glass back and liquid first, so the straw stands in the drink.
        ctx.saveGState()
        ctx.addPath(glass); ctx.setFillColor(NSColor(white: 1, alpha: 0.35).cgColor); ctx.fillPath()
        let level = cupY + cupH * (0.86 - 0.05 * climb)
        ctx.addPath(glass); ctx.clip()
        ctx.setFillColor(NSColor.systemGreen.cgColor)
        ctx.fill(CGRect(x: cupX - cupW, y: cupY, width: cupW * 2, height: level - cupY))
        // The drink's surface, a lighter line just under the rim.
        ctx.setFillColor(NSColor(srgbRed: 0.6, green: 0.95, blue: 0.65, alpha: 1).cgColor)
        ctx.fill(CGRect(x: cupX - cupW, y: level - 0.7, width: cupW * 2, height: 0.7))
        ctx.restoreGState()

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
        // Ridges where it bends.
        ctx.saveGState(); ctx.addPath(outer); ctx.clip()
        ctx.setStrokeColor(darkRed); ctx.setLineWidth(0.35)
        for k in 1...3 {
            let y = bend.y - CGFloat(k) * 0.7
            ctx.move(to: CGPoint(x: bend.x - w, y: y)); ctx.addLine(to: CGPoint(x: bend.x + w, y: y))
        }
        ctx.strokePath(); ctx.restoreGState()

        // Glass front: the rim and sides over the straw, and a glint.
        ctx.saveGState()
        ctx.addPath(glass); ctx.setStrokeColor(edge); ctx.setLineWidth(0.55); ctx.setLineJoin(.round); ctx.strokePath()
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.8).cgColor); ctx.setLineWidth(0.4); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: cupX - cupW / 2 + 1.6, y: 0.5))
        ctx.addLine(to: CGPoint(x: cupX - cupW / 2 + 1.3, y: cupY + cupH - 1.6))
        ctx.strokePath()
        ctx.restoreGState()
    }
}
