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
/// charging; with a face, charging fills green and grins, and plugged-but-not-
/// charging shows a smiling plug instead), then an optional trailing text (e.g. the time). Drawn straight
/// into an NSImage — no PNG/base64 round-trip.
public enum BatteryGlyph {
    public static func image(
        pct: Int,
        charging: Bool,
        plugged: Bool = false,
        lead: String,
        trailing: String,
        ink: NSColor,
        fill fillKind: BatteryFill,
        face: Bool = false
    ) -> NSImage {
        let batteryPct = max(0, min(100, pct))
        // With a face: charging turns a plain fill green and the face happy;
        // plugged in but not charging (full, or macOS holding the charge at a
        // limit) swaps the whole battery for a smiling plug.
        let greenFill = face && charging && fillKind == .none
        let plugFace = face && plugged && !charging

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
        let plugW: CGFloat = 28, plugH: CGFloat = 13

        let glyphW: CGFloat = plugFace ? plugW : bodyW + nubW
        let leadGap: CGFloat = (!lead.isEmpty && glyphW > 0) ? gap : 0
        let trailGap: CGFloat = (!trailing.isEmpty && (glyphW > 0 || !lead.isEmpty)) ? gap : 0
        let width = max(1, ceil(leadSize.width + leadGap + glyphW + trailGap + textSize.width))
        let height = max(1, ceil(max(fontH, leadSize.height, textSize.height, plugFace ? plugH : bodyH)))

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
            ink.setStroke(); bodyPath.stroke()
            let nub = NSBezierPath(roundedRect: NSRect(x: originX + bodyW - lineW, y: (height - nubH)/2, width: nubW, height: nubH), xRadius: 0.9, yRadius: 0.9)
            ink.setFill(); nub.fill()
            let innerW = bodyRect.width - 2*fillInset
            let fillRect = NSRect(x: bodyRect.minX + fillInset, y: bodyRect.minY + fillInset,
                                  width: max(0, innerW * CGFloat(pctValue)/100.0), height: bodyRect.height - 2*fillInset)
            (greenFill ? NSColor.systemGreen : fill).setFill(); NSBezierPath(roundedRect: fillRect, xRadius: 1.3 * k, yRadius: 1.3 * k).fill()

            let cx = originX + bodyW/2, cy = height/2
            if face {
                // The mascot's face: two eyes and a mouth whose mood follows the
                // charge — a smile when full, a flat "meh" line around half, a slight
                // frown when getting low, and a full frown when low. Charging, it
                // grins with happy ^ ^ eyes.
                let eye = bodyH * 0.15
                let low = fillKind == .red
                let eyeY = cy + bodyH * 0.08
                let eyeXs = [cx - bodyW * 0.17, cx + bodyW * 0.17]
                let mouthLW = max(0.9, bodyH * 0.08)
                var eyePaths: [NSBezierPath] = []
                if charging {
                    // happy closed eyes: ^ ^
                    for ex in eyeXs {
                        let e = NSBezierPath()
                        e.move(to: NSPoint(x: ex - eye * 0.8, y: eyeY + eye * 0.2))
                        e.line(to: NSPoint(x: ex, y: eyeY + eye * 1.0))
                        e.line(to: NSPoint(x: ex + eye * 0.8, y: eyeY + eye * 0.2))
                        e.lineWidth = mouthLW; e.lineCapStyle = .round; e.lineJoinStyle = .round
                        eyePaths.append(e)
                    }
                }
                let eyes = eyeXs.map { NSRect(x: $0 - eye/2, y: eyeY, width: eye, height: eye) }
                let mouth = NSBezierPath()
                var mouthFilled = false
                let halfW = bodyH * 0.17
                if charging {
                    // an open grin: a half-disc
                    mouth.appendArc(withCenter: NSPoint(x: cx, y: cy - bodyH * 0.06), radius: bodyH * 0.2, startAngle: 180, endAngle: 360, clockwise: false)
                    mouth.close(); mouthFilled = true
                } else if low {
                    mouth.appendArc(withCenter: NSPoint(x: cx, y: cy - bodyH * 0.34), radius: bodyH * 0.2, startAngle: 35, endAngle: 145, clockwise: false)
                } else {
                    // sag of the mouth: a smile from 60%, flat from 35%, a slight frown below
                    let sag: CGFloat = pctValue >= 60 ? bodyH * 0.085 : pctValue >= 35 ? 0 : -bodyH * 0.04
                    let endY = cy - bodyH * 0.1 - (bodyH * 0.085 - sag) / 2
                    mouth.move(to: NSPoint(x: cx - halfW, y: endY))
                    mouth.curve(to: NSPoint(x: cx + halfW, y: endY),
                                controlPoint1: NSPoint(x: cx - halfW * 0.5, y: endY - sag * 1.33),
                                controlPoint2: NSPoint(x: cx + halfW * 0.5, y: endY - sag * 1.33))
                }
                mouth.lineWidth = mouthLW; mouth.lineCapStyle = .round
                let draw = {
                    if eyePaths.isEmpty { for e in eyes { NSBezierPath(ovalIn: e).fill() } }
                    else { for e in eyePaths { e.stroke() } }
                    if mouthFilled { mouth.fill() } else { mouth.stroke() }
                }
                // The face straddles the fill's edge, so it is split there. Over a
                // yellow fill it is black (a knocked-out hole shows the bar, which
                // is too light to read on yellow in light mode); over any other
                // fill it is knocked out (reads as a hole in the charge). Over the
                // empty part it is drawn in ink (a hole in nothing is invisible).
                let split = fillRect.maxX
                let filled = NSRect(x: bodyRect.minX, y: bodyRect.minY, width: max(0, split - bodyRect.minX), height: bodyRect.height)
                let empty = NSRect(x: split, y: bodyRect.minY, width: max(0, bodyRect.maxX - split), height: bodyRect.height)
                if filled.width > 0 {
                    if fillKind == .yellow {
                        NSGraphicsContext.current?.saveGraphicsState()
                        NSBezierPath(rect: filled).setClip()
                        NSColor.black.set(); draw()
                        NSGraphicsContext.current?.restoreGraphicsState()
                    } else {
                        knockout(draw, clip: filled)
                    }
                }
                if empty.width > 0 {
                    NSGraphicsContext.current?.saveGraphicsState()
                    NSBezierPath(rect: empty).setClip()
                    ink.set(); draw()
                    NSGraphicsContext.current?.restoreGraphicsState()
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

        // Plugged in but not charging (with a face): a smiling plug in the
        // battery's place — cord on the left, prongs to the right, and the face
        // knocked out of its body.
        func drawPlug(originX: CGFloat) {
            let cy = height/2
            ink.set()
            // the cord, curling in from the left
            let cord = NSBezierPath()
            cord.move(to: NSPoint(x: originX + 0.8, y: cy - 3.2))
            cord.curve(to: NSPoint(x: originX + 4, y: cy), controlPoint1: NSPoint(x: originX + 2.8, y: cy - 3.6), controlPoint2: NSPoint(x: originX + 2.2, y: cy))
            cord.lineWidth = 1.5; cord.lineCapStyle = .round
            cord.stroke()
            // strain-relief boot tapering from the cord into the body, with two grip rings
            let boot = NSBezierPath()
            boot.move(to: NSPoint(x: originX + 3.6, y: cy - 1.3)); boot.line(to: NSPoint(x: originX + 7, y: cy - 3))
            boot.line(to: NSPoint(x: originX + 7, y: cy + 3)); boot.line(to: NSPoint(x: originX + 3.6, y: cy + 1.3)); boot.close()
            boot.fill()
            // the body
            let body = NSRect(x: originX + 6.5, y: cy - plugH/2, width: 13.5, height: plugH)
            NSBezierPath(roundedRect: body, xRadius: 3.4, yRadius: 3.4).fill()
            // the collar the prongs come out of
            let collar = NSRect(x: body.maxX - 0.6, y: cy - 4.2, width: 2.6, height: 8.4)
            NSBezierPath(roundedRect: collar, xRadius: 1, yRadius: 1).fill()
            // the prongs, each with its hole near the tip
            let prongs = [-2.6, 2.6].map { (dy: CGFloat) in
                NSRect(x: collar.maxX - 0.4, y: cy + dy - 0.95, width: 6, height: 1.9)
            }
            for r in prongs { NSBezierPath(roundedRect: r, xRadius: 0.5, yRadius: 0.5).fill() }
            let fx = body.midX, eye = plugH * 0.15
            knockout {
                for x in [originX + 4.9, originX + 5.9] {
                    NSBezierPath(rect: NSRect(x: x, y: cy - 3, width: 0.45, height: 6)).fill()
                }
                // seam between the body and the collar
                NSBezierPath(rect: NSRect(x: body.maxX - 0.35, y: cy - 4.2, width: 0.5, height: 8.4)).fill()
                for r in prongs {
                    NSBezierPath(ovalIn: NSRect(x: r.maxX - 2.1, y: r.midY - 0.45, width: 0.9, height: 0.9)).fill()
                }
                // the face, with a little shine on the body's shoulder
                for ex in [fx - 3, fx + 3] {
                    NSBezierPath(ovalIn: NSRect(x: ex - eye/2, y: cy + 0.9, width: eye, height: eye)).fill()
                }
                let smile = NSBezierPath()
                smile.appendArc(withCenter: NSPoint(x: fx, y: cy + 0.4), radius: plugH * 0.2, startAngle: 215, endAngle: 325, clockwise: false)
                smile.lineWidth = max(0.9, plugH * 0.08); smile.lineCapStyle = .round
                smile.stroke()
                let shine = NSBezierPath()
                shine.appendArc(withCenter: NSPoint(x: body.minX + 3.4, y: body.maxY - 3.4), radius: 2.2, startAngle: 105, endAngle: 165, clockwise: false)
                shine.lineWidth = 0.7; shine.lineCapStyle = .round
                shine.stroke()
            }
        }

        let img = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            if !lead.isEmpty {
                leadStr.draw(at: NSPoint(x: x, y: (height - leadSize.height)/2))
                x += leadSize.width + leadGap
            }
            if plugFace { drawPlug(originX: x) } else { drawBattery(batteryPct, originX: x) }
            x += glyphW + trailGap
            if !trailing.isEmpty {
                textStr.draw(at: NSPoint(x: x, y: (height - textSize.height)/2))
            }
            return true
        }

        // the green charging fill needs colour, so it is never a template
        img.isTemplate = (fillKind == .none) && !greenFill
        return img
    }
}
