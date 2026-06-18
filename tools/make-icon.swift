#!/usr/bin/env swift
//
// Renders the Claude Footswitch app icon at every macOS iconset size.
// A Claude-coral rounded-rectangle tile with a white "shoeprints" glyph
// (the same motif as the menu-bar icon).
//
//   swift tools/make-icon.swift [iconsetDir] [previewPath]
//
import AppKit

let arguments = CommandLine.arguments
let iconsetDir = arguments.count > 1 ? arguments[1] : "build/AppIcon.iconset"
let previewPath = arguments.count > 2 ? arguments[2] : "docs/icon.png"

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

/// A solid-white version of an SF Symbol image (template glyph → white fill).
func whiteSymbol(pointSize: CGFloat) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    guard let base = NSImage(systemSymbolName: "shoeprints.fill", accessibilityDescription: nil),
          let symbol = base.withSymbolConfiguration(config) else { return nil }
    let out = NSImage(size: symbol.size)
    out.lockFocus()
    symbol.draw(at: .zero, from: NSRect(origin: .zero, size: symbol.size), operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)

    // Build the white glyph up front (uses its own focus) before we take the canvas context.
    let glyph = whiteSymbol(pointSize: size * 0.5)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.set()
    canvas.fill()

    // Rounded-rectangle tile, following Apple's icon grid proportions.
    let margin = size * 0.094
    let body = canvas.insetBy(dx: margin, dy: margin)
    let radius = body.width * 0.2237
    let tile = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    if size >= 128 {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = size * 0.03
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
        shadow.set()
    }

    // Claude-coral gradient: lighter at top, deeper at bottom.
    let gradient = NSGradient(starting: srgb(240, 168, 124), ending: srgb(193, 91, 57))!
    gradient.draw(in: tile, angle: -90)
    NSShadow().set() // clear shadow before the glyph

    // White footprints, scaled to fit and centered (nudged up for optical balance).
    if let glyph {
        let maxExtent = body.height * 0.58
        let scale = min(maxExtent / glyph.size.width, maxExtent / glyph.size.height)
        let w = glyph.size.width * scale
        let h = glyph.size.height * scale
        let rect = NSRect(x: body.midX - w / 2, y: body.midY - h / 2 + body.height * 0.01, width: w, height: h)
        glyph.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("✕ failed to encode \(path)\n".utf8))
        return
    }
    try? data.write(to: URL(fileURLWithPath: path))
}

let files: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: (previewPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)

for file in files {
    writePNG(renderIcon(size: file.size), to: "\(iconsetDir)/\(file.name)")
}
writePNG(renderIcon(size: 1024), to: previewPath)
print("✓ Rendered \(files.count) PNGs into \(iconsetDir) and preview \(previewPath)")
