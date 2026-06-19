// render-title.swift
// Renders the menu-bar item to a tight PNG (base64 on stdout). Two modes, composed
// left-to-right: an optional battery glyph, then optional text.
//
//   Legacy/text:  render-title <text> [--bolt]
//   Battery icon: render-title --battery <0-100> [--battery-pct] [--charging]
//                              [--color none|red|yellow] [--text "<time>"]
//
// Only alpha matters for color=none (emit as templateImage so it adapts to
// light/dark); red/yellow produce a colored PNG (emit as image).

import AppKit

let argv = CommandLine.arguments
var text = "", withBolt = false, pctInside = false, charging = false, inkName = "black", fillName = ""
var batteryPct: Int? = nil
var i = 1
while i < argv.count {
  switch argv[i] {
  case "--bolt": withBolt = true
  case "--charging": charging = true
  case "--battery-pct": pctInside = true
  case "--battery": i += 1; if i < argv.count { batteryPct = max(0, min(100, Int(argv[i]) ?? 0)) }
  case "--ink": i += 1; if i < argv.count { inkName = argv[i] }
  case "--fill": i += 1; if i < argv.count { fillName = argv[i] }
  case "--text": i += 1; if i < argv.count { text = argv[i] }
  default: if !argv[i].hasPrefix("--") { text = argv[i] }
  }
  i += 1
}

// ink = outline / text / % color (the label color); fill = the battery-fill color
// (defaults to ink, so a plain mono icon emits as a template that auto-adapts).
let ink: NSColor = inkName == "white" ? .white : .black
let fill: NSColor = fillName == "yellow" ? .systemYellow : (fillName == "red" ? .systemRed : ink)

let scale: CGFloat = 2
let font = NSFont.menuBarFont(ofSize: 0)
let astr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
let textSize = text.isEmpty ? NSSize(width: 0, height: ceil(font.ascender - font.descender)) : astr.size()

// glyph metrics (points)
let bodyW: CGFloat = 22, bodyH: CGFloat = 11, nubW: CGFloat = 1.6, nubH: CGFloat = 4.2
let radius: CGFloat = 2.5, lineW: CGFloat = 1.0, fillInset: CGFloat = 1.6, gap: CGFloat = 3
let hasGlyph = batteryPct != nil

var boltImg: NSImage? = nil
if withBolt && !hasGlyph {
  let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
  boltImg = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
}

let leadW: CGFloat = hasGlyph ? (bodyW + nubW) : (boltImg?.size.width ?? 0)
let leadGap: CGFloat = (leadW > 0 && !text.isEmpty) ? gap : 0
let width = max(1, ceil(leadW + leadGap + textSize.width))
let height = max(1, ceil(max(textSize.height, bodyH, boltImg?.size.height ?? 0)))

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

func drawBattery(_ pct: Int, originX: CGFloat) {
  let by = (height - bodyH) / 2
  let bodyRect = NSRect(x: originX + lineW/2, y: by + lineW/2, width: bodyW - lineW, height: bodyH - lineW)
  let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: radius, yRadius: radius)
  bodyPath.lineWidth = lineW
  ink.setStroke(); bodyPath.stroke()
  let nub = NSBezierPath(roundedRect: NSRect(x: originX + bodyW - lineW, y: (height - nubH)/2, width: nubW, height: nubH), xRadius: 0.8, yRadius: 0.8)
  ink.setFill(); nub.fill()
  let innerW = bodyRect.width - 2*fillInset
  let fillRect = NSRect(x: bodyRect.minX + fillInset, y: bodyRect.minY + fillInset,
                        width: max(0, innerW * CGFloat(pct)/100.0), height: bodyRect.height - 2*fillInset)
  fill.setFill(); NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1).fill()
  if charging {
    let cfg = NSImage.SymbolConfiguration(pointSize: bodyH - 1.0, weight: .bold)
    if let b = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
      let r = NSRect(x: originX + bodyW/2 - b.size.width/2, y: (height - b.size.height)/2, width: b.size.width, height: b.size.height)
      knockout({ b.draw(in: r) })
    }
  }
  if pctInside {
    let ps = NSAttributedString(string: "\(pct)", attributes: [.font: NSFont.systemFont(ofSize: 7, weight: .semibold), .foregroundColor: ink])
    let psz = ps.size()
    let at = NSPoint(x: bodyRect.midX - psz.width/2, y: bodyRect.midY - psz.height/2)
    ps.draw(at: at)                                   // visible over the empty part
    knockout({ ps.draw(at: at) }, clip: fillRect)     // knocked out of the fill
  }
}

var x: CGFloat = 0
if hasGlyph { drawBattery(batteryPct!, originX: 0); x = leadW + leadGap }
else if let b = boltImg { b.draw(in: NSRect(x: 0, y: (height - b.size.height)/2, width: b.size.width, height: b.size.height)); x = leadW + leadGap }
if !text.isEmpty { astr.draw(at: NSPoint(x: x, y: (height - textSize.height)/2)) }

NSGraphicsContext.restoreGraphicsState()
FileHandle.standardOutput.write(Data(rep.representation(using: .png, properties: [:])!.base64EncodedString().utf8))
