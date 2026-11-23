import Accelerate
import CoreMedia
import CoreVideo
import UIKit

@available(iOS 15.0, *)
final class RemotePictureInPictureFrames {
    static let shared = RemotePictureInPictureFrames()

    private let lock = NSLock()
    private var display: Int?
    private var generation = 0
    private var longestEdge = 0
    private var interval: TimeInterval = 0
    private var lastFrame: TimeInterval = 0
    private var pending = false
    private var deliver: ((CVPixelBuffer, CMTime) -> Void)?

    func configure(display: Int?, longestEdge: Int, fps: Double,
                   deliver: ((CVPixelBuffer, CMTime) -> Void)?) {
        lock.lock()
        if self.display != display || self.longestEdge != longestEdge {
            generation += 1
            lastFrame = 0
        }
        self.display = display
        self.longestEdge = longestEdge
        interval = 1 / fps
        self.deliver = deliver
        lock.unlock()
    }

    func submit(_ display: Int, _ bytes: UnsafePointer<UInt8>, _ width: Int, _ height: Int, _ stride: Int) {
        guard width > 0, height > 0, stride / 4 >= width, lock.try() else { return }
        let now = CACurrentMediaTime()
        guard display == self.display, !pending, now - lastFrame >= interval else {
            lock.unlock()
            return
        }
        let generation = self.generation
        let longestEdge = self.longestEdge
        lastFrame = now
        pending = true
        lock.unlock()

        // The decoder reuses its storage as soon as this call returns.
        let scale = min(1, Double(longestEdge) / Double(max(width, height)))
        let buffer = Self.resize(bytes, width, height, stride,
                                 max(1, Int(Double(width) * scale)), max(1, Int(Double(height) * scale)))
        DispatchQueue.main.async { [self] in
            lock.lock()
            let deliver = generation == self.generation ? self.deliver : nil
            pending = false
            lock.unlock()
            if let buffer = buffer {
                deliver?(buffer, CMTime(seconds: now, preferredTimescale: 60000))
            }
        }
    }

    private static func resize(_ bytes: UnsafePointer<UInt8>, _ width: Int, _ height: Int, _ stride: Int,
                               _ outputWidth: Int, _ outputHeight: Int) -> CVPixelBuffer? {
        var storage: CVPixelBuffer?
        let options = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, outputWidth, outputHeight, kCVPixelFormatType_32BGRA,
                                  options, &storage) == kCVReturnSuccess,
              let buffer = storage,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let pixels = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var src = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: bytes),
                                height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: stride)
        var dst = vImage_Buffer(data: pixels, height: vImagePixelCount(outputHeight),
                                width: vImagePixelCount(outputWidth), rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        // Scaling is channel-independent, so it also works with BGRA byte order.
        guard vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return nil
        }
        return buffer
    }
}
