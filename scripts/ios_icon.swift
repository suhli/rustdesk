// Original geometric fork icon, drawn with the macOS SDK; no external artwork.
import AppKit
import Foundation

let directory = URL(fileURLWithPath: "flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset")
let contents = try Data(contentsOf: directory.appendingPathComponent("Contents.json"))
let manifest = try JSONSerialization.jsonObject(with: contents) as! [String: Any]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(red: 0.07, green: 0.16, blue: 0.25, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(red: 0.29, green: 0.89, blue: 0.76, alpha: 1).setStroke()
let screen = NSBezierPath(roundedRect: NSRect(x: 190, y: 300, width: 644, height: 442), xRadius: 56, yRadius: 56)
screen.lineWidth = 42; screen.stroke()
let stand = NSBezierPath()
stand.move(to: NSPoint(x: 512, y: 285)); stand.line(to: NSPoint(x: 512, y: 215))
stand.move(to: NSPoint(x: 385, y: 215)); stand.line(to: NSPoint(x: 639, y: 215))
stand.lineWidth = 42; stand.stroke()
NSColor.white.setStroke()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 372, y: 440)); arrow.line(to: NSPoint(x: 647, y: 625))
arrow.move(to: NSPoint(x: 512, y: 625)); arrow.line(to: NSPoint(x: 647, y: 625)); arrow.line(to: NSPoint(x: 647, y: 490))
arrow.lineWidth = 44; arrow.stroke()
image.unlockFocus()
for item in manifest["images"] as! [[String: Any]] {
    guard let file = item["filename"] as? String, let size = item["size"] as? String,
          let scale = item["scale"] as? String,
          let points = Double(size.components(separatedBy: "x")[0]),
          let multiplier = Double(scale.replacingOccurrences(of: "x", with: "")) else { continue }
    let pixels = Int(points * multiplier)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try png.write(to: directory.appendingPathComponent(file))
}
