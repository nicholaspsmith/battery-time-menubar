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
public enum BatteryGlyph {
    public static func image(
        pct: Int,
        charging: Bool,
        lead: String,
        trailing: String,
        ink: NSColor,
        fill fillKind: BatteryFill
    ) -> NSImage {
        let batteryPct = max(0, min(100, pct))

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

        // battery glyph metrics (points)
        let bodyW: CGFloat = 26, bodyH: CGFloat = 13, nubW: CGFloat = 2, nubH: CGFloat = 5.5
        let radius: CGFloat = 3.2, lineW: CGFloat = 1.2, fillInset: CGFloat = 1.3, gap: CGFloat = 4

        let glyphW: CGFloat = bodyW + nubW
        let leadGap: CGFloat = (!lead.isEmpty && glyphW > 0) ? gap : 0
        let trailGap: CGFloat = (!trailing.isEmpty && (glyphW > 0 || !lead.isEmpty)) ? gap : 0
        let width = max(1, ceil(leadSize.width + leadGap + glyphW + trailGap + textSize.width))
        let height = max(1, ceil(max(fontH, leadSize.height, textSize.height, bodyH)))

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
            fill.setFill(); NSBezierPath(roundedRect: fillRect, xRadius: 1.3, yRadius: 1.3).fill()

            let cx = originX + bodyW/2, cy = height/2
            if charging {
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
            drawBattery(batteryPct, originX: x)
            x += glyphW + trailGap
            if !trailing.isEmpty {
                textStr.draw(at: NSPoint(x: x, y: (height - textSize.height)/2))
            }
            return true
        }

        img.isTemplate = (fillKind == .none)
        return img
    }
}
