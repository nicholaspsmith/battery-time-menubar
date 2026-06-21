// render-title.swift
// Renders the menu-bar item to a tight PNG (base64 on stdout), composed
// left-to-right: optional lead text (e.g. "82%"), an optional battery glyph
// (or a standalone bolt), then optional trailing text (e.g. the time).
//
//   render-title --battery <0-100> [--charging|--flex] [--lead "82%"] [--text "1:20"]
//                [--ink black|white] [--fill none|yellow|red]
//   render-title [--bolt] [--text "1:20"]        # iconless / standalone-bolt fallback
//
// The battery glyph mirrors the native menu-bar icon: rounded body + nub, a fill
// proportional to charge, the % shown to its LEFT (not inside). A bisecting
// overlay marks state: a bolt while charging, the 💪 emoji in High Power mode.
//
// fill=none AND no emoji overlay emits a template image (alpha only, adapts to
// light/dark). A colored fill (yellow/red) or the 💪 overlay emits a normal
// colored PNG, so the caller picks ink to suit the current appearance.

import AppKit

let argv = CommandLine.arguments
var leadText = "", text = "", withBolt = false, charging = false, flex = false
var inkName = "black", fillName = "none"
var batteryPct: Int? = nil
var i = 1
while i < argv.count {
  switch argv[i] {
  case "--bolt": withBolt = true
  case "--charging": charging = true
  case "--flex": flex = true
  case "--battery": i += 1; if i < argv.count { batteryPct = max(0, min(100, Int(argv[i]) ?? 0)) }
  case "--lead": i += 1; if i < argv.count { leadText = argv[i] }
  case "--text": i += 1; if i < argv.count { text = argv[i] }
  case "--ink": i += 1; if i < argv.count { inkName = argv[i] }
  case "--fill": i += 1; if i < argv.count { fillName = argv[i] }
  default: if !argv[i].hasPrefix("--") { text = argv[i] }
  }
  i += 1
}

// ink = outline / text / % / bolt color (the label color); fill = battery-fill color
// (defaults to ink, so a plain mono icon emits as a template that auto-adapts).
let ink: NSColor = inkName == "white" ? .white : .black
let fill: NSColor = fillName == "yellow" ? .systemYellow : (fillName == "red" ? .systemRed : ink)

let scale: CGFloat = 2
// the % / time text run 2pt smaller than the default menu-bar font
let font = NSFont.menuBarFont(ofSize: max(1, NSFont.menuBarFont(ofSize: 0).pointSize - 2))
func attr(_ s: String) -> NSAttributedString {
  NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: ink])
}
let leadStr = attr(leadText), textStr = attr(text)
let leadSize = leadText.isEmpty ? NSSize.zero : leadStr.size()
let textSize = text.isEmpty ? NSSize.zero : textStr.size()
let fontH = ceil(font.ascender - font.descender)

// battery glyph metrics (points) — a little bigger than before, like the native icon
let bodyW: CGFloat = 26, bodyH: CGFloat = 13, nubW: CGFloat = 2, nubH: CGFloat = 5.5
let radius: CGFloat = 3.2, lineW: CGFloat = 1.2, fillInset: CGFloat = 1.3, gap: CGFloat = 4
let hasGlyph = batteryPct != nil

var boltImg: NSImage? = nil
if withBolt && !hasGlyph {
  let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
  boltImg = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
}

let glyphW: CGFloat = hasGlyph ? (bodyW + nubW) : (boltImg?.size.width ?? 0)
let leadGap: CGFloat = (!leadText.isEmpty && glyphW > 0) ? gap : 0
let trailGap: CGFloat = (!text.isEmpty && (glyphW > 0 || !leadText.isEmpty)) ? gap : 0
let width = max(1, ceil(leadSize.width + leadGap + glyphW + trailGap + textSize.width))
let height = max(1, ceil(max(fontH, leadSize.height, textSize.height, bodyH, boltImg?.size.height ?? 0)))

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width*scale), pixelsHigh: Int(height*scale),
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func knockout(_ block: () -> Void, clip: NSRect? = nil) {
  NSGraphicsContext.current?.saveGraphicsState()
  if let c = clip { NSBezierPath(rect: c).setClip() }
  NSGraphicsContext.current?.compositingOperation = .destinationOut
  block()
  NSGraphicsContext.current?.restoreGraphicsState()
}

// Recolor whatever was already drawn within rect to `c` (e.g. tint a glyph to ink).
func tint(_ rect: NSRect, _ c: NSColor) {
  NSGraphicsContext.current?.saveGraphicsState()
  NSGraphicsContext.current?.compositingOperation = .sourceAtop
  c.set(); NSBezierPath(rect: rect).fill()
  NSGraphicsContext.current?.restoreGraphicsState()
}

// A lightning bolt as a bezier path, centered/scaled into `rect`. Normalized
// vertices (y-up) of a ⚡ shape, mapped so its bounding box fills the rect — so
// we control the exact size/centering (SF Symbol padding does not cooperate).
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

func drawBattery(_ pct: Int, originX: CGFloat) {
  let by = (height - bodyH) / 2
  let bodyRect = NSRect(x: originX + lineW/2, y: by + lineW/2, width: bodyW - lineW, height: bodyH - lineW)
  let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: radius, yRadius: radius)
  bodyPath.lineWidth = lineW
  ink.setStroke(); bodyPath.stroke()
  let nub = NSBezierPath(roundedRect: NSRect(x: originX + bodyW - lineW, y: (height - nubH)/2, width: nubW, height: nubH), xRadius: 0.9, yRadius: 0.9)
  ink.setFill(); nub.fill()
  let innerW = bodyRect.width - 2*fillInset
  let fillRect = NSRect(x: bodyRect.minX + fillInset, y: bodyRect.minY + fillInset,
                        width: max(0, innerW * CGFloat(pct)/100.0), height: bodyRect.height - 2*fillInset)
  fill.setFill(); NSBezierPath(roundedRect: fillRect, xRadius: 1.3, yRadius: 1.3).fill()

  let cx = originX + bodyW/2, cy = height/2
  if charging {
    // a bolt bisecting the glyph like the native charging icon: a CUTOUT (the
    // background shows through, so it's a different colour from the fill and bold
    // even on a full battery) finished with a crisp ink border so it stays
    // defined over both the filled and empty parts of the body.
    let boltH = bodyH - 1.5, boltW = boltH * 0.79
    let r = NSRect(x: cx - boltW/2, y: cy - boltH/2, width: boltW, height: boltH)
    let path = boltPath(in: r)
    knockout({ path.fill() })
    path.lineWidth = 1.0; ink.setStroke(); path.stroke()
  } else if flex {
    // High Power mode: a 💪 emoji bisecting the glyph (colored; same halo trick).
    let ef = NSFont.systemFont(ofSize: bodyH - 2)
    let es = NSAttributedString(string: "💪", attributes: [.font: ef])
    let sz = es.size()
    let r = NSRect(x: cx - sz.width/2, y: cy - sz.height/2, width: sz.width, height: sz.height)
    let halo: CGFloat = 1.6
    knockout({ es.draw(in: NSRect(x: r.minX-halo/2, y: r.minY-halo/2, width: r.width+halo, height: r.height+halo)) })
    es.draw(in: r)
  }
}

var x: CGFloat = 0
if !leadText.isEmpty { leadStr.draw(at: NSPoint(x: x, y: (height - leadSize.height)/2)); x += leadSize.width + leadGap }
if hasGlyph { drawBattery(batteryPct!, originX: x); x += glyphW + trailGap }
else if let b = boltImg { b.draw(in: NSRect(x: x, y: (height - b.size.height)/2, width: b.size.width, height: b.size.height)); x += glyphW + trailGap }
if !text.isEmpty { textStr.draw(at: NSPoint(x: x, y: (height - textSize.height)/2)) }

NSGraphicsContext.restoreGraphicsState()
FileHandle.standardOutput.write(Data(rep.representation(using: .png, properties: [:])!.base64EncodedString().utf8))
