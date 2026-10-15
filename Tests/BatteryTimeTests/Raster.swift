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
