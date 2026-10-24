// Compose a share card from the app's own --preview output. No duplicated icon renderer.
import AppKit
let args = CommandLine.arguments
precondition(args.count == 3, "Usage: swift scripts/render-marketing.swift preview.png hero.png")
let _ = NSApplication.shared
let preview = NSImage(contentsOfFile: args[1])!
preview.size = NSSize(width: 370, height: 100)
let canvas = NSImage(size: NSSize(width: 1280, height: 640), flipped: false) { _ in
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1280, height: 640).fill()
    func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        value.draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }
    text("CODEX BATTERY", x: 76, y: 548, size: 22, weight: .semibold, color: NSColor(calibratedWhite: 0.72, alpha: 1))
    text("Your quota.", x: 72, y: 384, size: 88, weight: .bold, color: .white)
    text("At a glance.", x: 72, y: 282, size: 88, weight: .bold, color: .white)
    text("A native macOS menu bar companion.", x: 78, y: 214, size: 25, weight: .regular, color: NSColor(calibratedWhite: 0.75, alpha: 1))
    for (row, index) in [0, 2, 4].enumerated() {
        preview.draw(in: NSRect(x: 923, y: 394 - row * 124, width: 215, height: 110),
                     from: NSRect(x: 13 + index * 60, y: 14, width: 43, height: 22), operation: .sourceOver, fraction: 1)
    }
    text("Actual icon renderings · example quotas", x: 845, y: 100, size: 16, weight: .regular, color: NSColor(calibratedWhite: 0.61, alpha: 1))
    NSColor(calibratedWhite: 0.26, alpha: 1).setFill()
    NSRect(x: 78, y: 132, width: 655, height: 1).fill()
    text("LIVE QUOTAS     CUSTOM COLORS     OPEN SOURCE", x: 78, y: 86, size: 17, weight: .medium, color: NSColor(calibratedWhite: 0.70, alpha: 1))
    text("github.com/AdvancingTitans/codex-battery", x: 78, y: 44, size: 17, weight: .regular, color: NSColor(calibratedWhite: 0.54, alpha: 1))
    return true
}
// Encode at exactly 1280 × 640 for GitHub's social preview.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 640, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
canvas.draw(in: NSRect(x: 0, y: 0, width: 1280, height: 640))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
