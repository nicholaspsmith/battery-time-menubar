// render-title.swift
// Renders menu-bar text (optionally preceded by a small bolt) into a tight,
// transparent TEMPLATE png and prints it base64-encoded on stdout. Used by
// battery-time.5s.sh so the menu-bar item sits as tightly as the icon-based
// items (SwiftBar pads text items wider than images).
//
//   Usage: render-title <text> [--bolt]
//
// Compiled once at install time (see install.sh). Only the alpha channel
// matters — SwiftBar's templateImage= renders it in the menu-bar label color
// and adapts to light/dark automatically.

import AppKit

let args = CommandLine.arguments
let text = args.count > 1 ? args[1] : ""
let withBolt = args.contains("--bolt")

let textFont = NSFont.menuBarFont(ofSize: 0)   // default menu-bar font + size
let boltPointSize: CGFloat = 11                 // small bolt (tunable)
let gap: CGFloat = 1.5                           // bolt <-> text gap
let scaleFactor: CGFloat = 2                     // retina

let attrs: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: NSColor.black]
let astr = NSAttributedString(string: text, attributes: attrs)
let textSize = text.isEmpty
    ? NSSize(width: 0, height: ceil(textFont.ascender - textFont.descender))
    : astr.size()

var boltImage: NSImage? = nil
if withBolt {
    let cfg = NSImage.SymbolConfiguration(pointSize: boltPointSize, weight: .regular)
    boltImage = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg)
}
let boltAdvance: CGFloat = boltImage != nil
    ? boltImage!.size.width + (text.isEmpty ? 0 : gap)
    : 0

let width  = max(1, ceil(boltAdvance + textSize.width))
let height = max(1, ceil(max(textSize.height, boltImage?.size.height ?? 0)))

guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scaleFactor), pixelsHigh: Int(height * scaleFactor),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

if let b = boltImage {
    let y = (height - b.size.height) / 2
    b.draw(in: NSRect(x: 0, y: y, width: b.size.width, height: b.size.height),
           from: .zero, operation: .sourceOver, fraction: 1.0)
}
if !text.isEmpty {
    let y = (height - textSize.height) / 2
    astr.draw(at: NSPoint(x: boltAdvance, y: y))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
FileHandle.standardOutput.write(Data(png.base64EncodedString().utf8))
