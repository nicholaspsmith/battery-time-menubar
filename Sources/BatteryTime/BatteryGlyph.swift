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
        blink: CGFloat? = nil
    ) -> NSImage {
        // Animation inputs, each nil when still:
        // - sip: 0..<1 through one sip while charging (a bead of charge runs
        //   down the straw into his mouth).
        // - slosh: 0...1 through the once-a-minute slosh on battery (the fill
        //   tilts side to side like liquid in a jar, and he grins).
        // - burp: 0...1 through the once-a-minute burp while stuffed.
        // - blink: 0...1 through the once-a-minute blink on battery.
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
                    let gulp: CGFloat = sip.map { $0 > 0.55 && $0 < 0.8 ? sin(.pi * ($0 - 0.55) / 0.25) : 0 } ?? 0
                    let r = bodyH * (0.085 + 0.035 * gulp)
                    fills.append(NSBezierPath(ovalIn: NSRect(x: cx - r, y: mouthY - r, width: r * 2, height: r * 2)))
                } else if stuffed {
                    // A small closed mouth. The burp opens it for a moment, with
                    // little cheeks either side while it lasts.
                    let b = burp ?? 0
                    let burping = b > 0.2 && b < 0.75
                    for side in [-1.0, 1.0] as [CGFloat] where burping {
                        let rx = bodyH * 0.077, ry = bodyH * 0.063
                        let x = cx + side * bodyW * 0.2
                        fills.append(NSBezierPath(ovalIn: NSRect(x: x - rx, y: mouthY - bodyH * 0.03 - ry, width: rx * 2, height: ry * 2)))
                    }
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
                    // The straw: a bendy one coming up from below the battery,
                    // bent just enough — well short of a right angle — for its
                    // top to reach his mouth. White with candy stripes that run
                    // diagonally right across it, outlined in ink so it reads on
                    // a light bar and a dark one.
                    let lips = NSPoint(x: cx + bodyH * 0.08, y: mouthY)
                    let run = bodyW * 0.2 - bodyH * 0.08
                    let bend = NSPoint(x: lips.x + run, y: mouthY - run * 0.7)
                    let base = NSPoint(x: bend.x, y: 0.9)
                    let straw = NSBezierPath()
                    straw.move(to: base)
                    straw.line(to: bend)
                    straw.line(to: lips)
                    straw.lineCapStyle = .round; straw.lineJoinStyle = .round
                    straw.lineWidth = 2.8; ink.setStroke(); straw.stroke()
                    straw.lineWidth = 2.0; NSColor.white.setStroke(); straw.stroke()
                    if let ctx = NSGraphicsContext.current?.cgContext {
                        // Clip to the straw's white body, then lay diagonal stripes
                        // across the whole width so each band meets the outline.
                        let cg = CGMutablePath()
                        cg.move(to: base); cg.addLine(to: bend); cg.addLine(to: lips)
                        ctx.saveGState()
                        ctx.addPath(cg.copy(strokingWithWidth: 2.0, lineCap: .round, lineJoin: .round, miterLimit: 4))
                        ctx.clip()
                        ctx.setStrokeColor(NSColor.systemPink.cgColor)
                        ctx.setLineWidth(0.85)
                        var x = lips.x - 6
                        while x < base.x + 4 {
                            ctx.move(to: CGPoint(x: x, y: base.y - 1)); ctx.addLine(to: CGPoint(x: x + 14, y: base.y + 13))
                            x += 1.9
                        }
                        ctx.strokePath()
                        ctx.restoreGState()
                    }
                    // A bead of charge running up it and across into his mouth.
                    if let t = sip, t < 0.6 {
                        let u = t / 0.6
                        let rise = bend.y - base.y, across = hypot(bend.x - lips.x, bend.y - lips.y)
                        let d = u * (rise + across)
                        let at = d < rise ? NSPoint(x: base.x, y: base.y + d)
                            : NSPoint(x: bend.x + (lips.x - bend.x) * (d - rise) / across,
                                      y: bend.y + (lips.y - bend.y) * (d - rise) / across)
                        let r: CGFloat = 0.85
                        NSColor.systemGreen.blended(withFraction: 0.25, of: .black)?.setFill()
                        NSBezierPath(ovalIn: NSRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)).fill()
                    }
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
}
