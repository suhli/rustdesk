import AppKit
import Foundation

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fatalError("Icon inspection command failed: \(executable)")
    }
}

let manager = FileManager.default
guard CommandLine.arguments.count > 1 else { fatalError("Pass one or more IPA paths") }
for path in CommandLine.arguments.dropFirst() {
    let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        do { try manager.removeItem(at: directory) }
        catch { fputs("Could not remove icon inspection directory: \(error)\n", stderr) }
    }
    try run("/usr/bin/ditto", ["-x", "-k", path, directory.path])
    let apps = try manager.contentsOfDirectory(at: directory.appendingPathComponent("Payload"),
        includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
    guard apps.count == 1 else { fatalError("Expected exactly one app in \(path)") }
    let app = apps[0]
    let info = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: app.appendingPathComponent("Info.plist")),
        options: [], format: nil) as! [String: Any]
    let files = try manager.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)
    var icons = Set<URL>()
    for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
        guard let group = info[key] as? [String: Any],
              let primary = group["CFBundlePrimaryIcon"] as? [String: Any],
              let names = primary["CFBundleIconFiles"] as? [String], !names.isEmpty else {
            fatalError("Missing primary icon files for \(key) in \(path)")
        }
        for name in names {
            let base = (name as NSString).deletingPathExtension
            let matches = files.filter {
                let stem = $0.deletingPathExtension().lastPathComponent
                return $0.pathExtension == "png" &&
                    (stem == base || stem.hasPrefix(base + "@") || stem.hasPrefix(base + "~"))
            }
            guard !matches.isEmpty else { fatalError("Missing packaged icon: \(name)") }
            icons.formUnion(matches)
        }
    }
    for file in icons.sorted(by: { $0.path < $1.path }) {
        let decoded = directory.appendingPathComponent(file.lastPathComponent)
        // Xcode's CgBI PNGs must be decoded before AppKit can inspect their pixels.
        try run("/usr/bin/xcrun", ["-sdk", "iphoneos", "pngcrush",
            "-revert-iphone-optimizations", "-q", file.path, decoded.path])
        let data = try Data(contentsOf: decoded)
        guard let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0, bitmap.pixelsWide == bitmap.pixelsHigh else {
            fatalError("Invalid packaged icon: \(file.lastPathComponent)")
        }
        var darkest = CGFloat(1), brightest = CGFloat(0)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 16)) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 16)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent >= 0.999 else {
                    fatalError("Unreadable or transparent packaged icon: \(file.lastPathComponent)")
                }
                let brightness = max(color.redComponent, max(color.greenComponent, color.blueComponent))
                darkest = min(darkest, brightness)
                brightest = max(brightest, brightness)
            }
        }
        guard brightest - darkest >= 0.25 else {
            fatalError("Packaged icon is blank or lacks visible artwork: \(file.lastPathComponent)")
        }
        print("Validated packaged icon: \(file.lastPathComponent)")
    }
    let build = info["CFBundleVersion"] as? String ?? "unknown"
    print("Validated \(path), build \(build)")
}
