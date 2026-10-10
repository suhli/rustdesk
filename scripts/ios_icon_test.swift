import AppKit
import Foundation

let directory = URL(fileURLWithPath: "flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset")
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("Contents.json"))) as! [String: Any]
for item in manifest["images"] as! [[String: Any]] {
    let file = item["filename"] as! String
    let points = Double((item["size"] as! String).components(separatedBy: "x")[0])!
    let scale = Double((item["scale"] as! String).replacingOccurrences(of: "x", with: ""))!
    let pixels = Int(points * scale)
    let data = try Data(contentsOf: directory.appendingPathComponent(file))
    guard let bitmap = NSBitmapImageRep(data: data),
          bitmap.pixelsWide == pixels, bitmap.pixelsHigh == pixels, !bitmap.hasAlpha else {
        fatalError("Icon must be an opaque \(pixels)x\(pixels) PNG: \(file)")
    }
    var colors = Set<Int>()
    for y in stride(from: 0, to: pixels, by: max(1, pixels / 16)) {
        for x in stride(from: 0, to: pixels, by: max(1, pixels / 16)) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                fatalError("Cannot read icon pixels: \(file)")
            }
            colors.insert((Int(color.redComponent * 255) << 16)
                | (Int(color.greenComponent * 255) << 8) | Int(color.blueComponent * 255))
        }
    }
    guard colors.count > 1 else { fatalError("Icon is a solid color: \(file)") }
}
print("All app icons have the expected size, are opaque, and contain visible artwork.")
