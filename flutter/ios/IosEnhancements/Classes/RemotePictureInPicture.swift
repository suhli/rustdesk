import AVFoundation
import AVKit
import Flutter
import UIKit

@available(iOS 15.0, *)
private final class RemotePictureInPictureView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var videoLayer: AVSampleBufferDisplayLayer? { layer as? AVSampleBufferDisplayLayer }
}

@available(iOS 15.0, *)
final class RemotePictureInPicture: NSObject, AVPictureInPictureControllerDelegate,
                                   AVPictureInPictureSampleBufferPlaybackDelegate {
    private weak var host: FlutterViewController?
    private let channel: FlutterMethodChannel
    private let source = RemotePictureInPictureView()
    private var controller: AVPictureInPictureController?
    private var possible: NSKeyValueObservation?
    private var suspended: NSKeyValueObservation?
    private var owner: String?
    private var display = 0
    private var crop: CGRect?
    private var automatic = false
    private var quality = "automatic"
    private var foreground = true
    private var dismissed = false
    private var playbackAudio = false
    private var live = true
    private var paused = false
    private var starting = false
    private var restoringUI = false
    private var request: DispatchWorkItem?
    private var backgroundPreparation: DispatchWorkItem?
    private var lastState = ""
    private var backgroundStart: TimeInterval?
    private var activeStart: TimeInterval?
    private var frames = 0

    init(_ host: FlutterViewController) {
        self.host = host
        channel = FlutterMethodChannel(name: "rustdesk/remote-pip", binaryMessenger: host.binaryMessenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(FlutterMethodNotImplemented); return }
            self.handle(call, result)
        }
    }

    private func handle(_ call: FlutterMethodCall, _ result: FlutterResult) {
        guard let args = call.arguments as? [String: Any], let token = args["owner"] as? String else {
            result(FlutterMethodNotImplemented); return
        }
        switch call.method {
        case "configure":
            guard let display = args["display"] as? Int, display >= 0,
                  let view = host?.viewIfLoaded, let container = view.superview else {
                result(false); return
            }
            if owner != token {
                clear()
                owner = token
                source.frame = view.frame
                source.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                source.isUserInteractionEnabled = false
                source.accessibilityElementsHidden = true
                // Use an inline source at the remote canvas bounds without intercepting Flutter input.
                container.insertSubview(source, belowSubview: view)
                guard let layer = source.videoLayer else { clear(); result(false); return }
                layer.videoGravity = .resizeAspect
                let controller = AVPictureInPictureController(contentSource: .init(
                    sampleBufferDisplayLayer: layer, playbackDelegate: self))
                controller.delegate = self
                self.controller = controller
                possible = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.startIfPossible() }
                }
                suspended = controller.observe(\.isPictureInPictureSuspended, options: [.new]) { [weak self] controller, _ in
                    DispatchQueue.main.async {
                        guard let self = self, self.controller === controller, controller.isPictureInPictureActive else { return }
                        self.report(controller.isPictureInPictureSuspended ? "suspended" : "active")
                    }
                }
            }
            let values = args["crop"] as? [Int]
            let crop = values.flatMap { values -> CGRect? in
                guard values.count == 4, values[0] >= 0, values[1] >= 0,
                      values[2] > 0, values[3] > 0 else { return nil }
                return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            }
            if self.display != display || (self.crop == nil) != (crop == nil) {
                source.videoLayer?.flushAndRemoveImage()
            }
            self.display = display
            self.crop = crop
            automatic = args["automatic"] as? Bool ?? true
            quality = args["quality"] as? String ?? "automatic"
            updateSource()
            result(true)
        case "toggle" where owner == token:
            guard let controller = controller, foreground, live, !starting else { result(false); return }
            if controller.isPictureInPictureActive {
                controller.stopPictureInPicture()
            } else if request == nil {
                dismissed = false
                let task = DispatchWorkItem { [weak self] in
                    guard let self = self, self.owner == token, self.request != nil else { return }
                    self.request = nil
                    self.report("failed")
                    self.updateSource()
                }
                request = task
                updateSource()
                startIfPossible()
                DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
            }
            result(true)
        case "connection" where owner == token:
            live = args["live"] as? Bool ?? false
            if !live {
                source.videoLayer?.flushAndRemoveImage()
                report("disconnected")
            } else if controller?.isPictureInPictureActive == true {
                report(controller?.isPictureInPictureSuspended == true ? "suspended" : "active")
            } else {
                report("ready")
            }
            controller?.invalidatePlaybackState()
            updateSource()
            result(nil)
        case "detach" where owner == token:
            clear()
            result(nil)
        default:
            result(nil)
        }
    }

    func setForeground(_ value: Bool) {
        foreground = value
        guard owner != nil else { return }
        if value {
            dismissed = false
            backgroundPreparation?.cancel()
            backgroundPreparation = nil
            if let start = backgroundStart {
                NSLog("Remote PiP returned after %.0f ms, state=%@", (CACurrentMediaTime() - start) * 1000, lastState)
            }
            backgroundStart = nil
        } else {
            backgroundStart = CACurrentMediaTime()
            if !starting && controller?.isPictureInPictureActive != true {
                request?.cancel()
                request = nil
                if automatic && live && !dismissed {
                    let task = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        self.backgroundPreparation = nil
                        if !self.starting && self.controller?.isPictureInPictureActive != true {
                            self.report("unavailable")
                        }
                        self.updateSource()
                    }
                    backgroundPreparation = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
                }
            }
        }
        updateSource()
    }

    private func updateSource() {
        let active = controller?.isPictureInPictureActive == true
        let armed = automatic && !dismissed
        let preparing = starting || request != nil || (armed && (foreground || backgroundPreparation != nil))
        let enabled = owner != nil && (active || preparing)
        if enabled && !playbackAudio {
            do {
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.playback, options: [.mixWithOthers])
                playbackAudio = true
                try audio.setActive(true)
            } catch {
                restoreAudio()
                NSLog("Remote PiP audio session failed: %@", error.localizedDescription)
            }
        } else if !enabled {
            restoreAudio()
        }
        controller?.canStartPictureInPictureAutomaticallyFromInline = armed && live && playbackAudio
        let saving = quality == "economy" || (quality == "automatic" && ProcessInfo.processInfo.isLowPowerModeEnabled)
        let flowing = enabled && playbackAudio && live && !paused
        RemotePictureInPictureFrames.shared.configure(
            display: flowing ? display : nil,
            crop: crop,
            longestEdge: active ? (saving ? 640 : quality == "high" ? 1280 : 960) : 640,
            fps: active ? (saving ? 8 : quality == "high" ? 24 : 15) : 6
        ) { [weak self] buffer, pts in
            self?.enqueue(buffer, pts)
        }
    }

    private func restoreAudio() {
        guard playbackAudio else { return }
        playbackAudio = false
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
        } catch {
            NSLog("Remote PiP could not restore audio mixing: %@", error.localizedDescription)
        }
    }

    private func enqueue(_ buffer: CVPixelBuffer, _ pts: CMTime) {
        guard let layer = source.videoLayer else { return }
        if layer.status == .failed || layer.requiresFlushToResumeDecoding { layer.flush() }
        guard layer.isReadyForMoreMediaData else { return }
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                           formatDescriptionOut: &format) == noErr,
              let format = format else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                       formatDescription: format, sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr,
              let sample = sample,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
              let attachment = CFArrayGetValueAtIndex(attachments, 0) else { return }
        CFDictionarySetValue(unsafeBitCast(attachment, to: CFMutableDictionary.self),
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        layer.enqueue(sample)
        if activeStart != nil { frames += 1 }
        startIfPossible()
    }

    private func startIfPossible() {
        guard let controller = controller, request != nil, foreground,
              controller.isPictureInPicturePossible, playbackAudio else { return }
        request?.cancel()
        request = nil
        backgroundPreparation?.cancel()
        backgroundPreparation = nil
        starting = true
        report("starting")
        controller.startPictureInPicture()
    }

    private func clear() {
        owner = nil
        request?.cancel()
        request = nil
        backgroundPreparation?.cancel()
        backgroundPreparation = nil
        possible = nil
        suspended = nil
        if let controller = controller {
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            controller.delegate = nil
            if controller.isPictureInPictureActive { controller.stopPictureInPicture() }
        }
        controller = nil
        crop = nil
        starting = false
        restoringUI = false
        dismissed = false
        live = true
        paused = false
        lastState = ""
        activeStart = nil
        updateSource()
        source.videoLayer?.flushAndRemoveImage()
        source.removeFromSuperview()
    }

    private func report(_ state: String) {
        guard let owner = owner, lastState != state else { return }
        lastState = state
        NSLog("Remote PiP: %@", state)
        channel.invokeMethod("state", arguments: ["owner": owner, "state": state, "background": !foreground])
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard controller === pictureInPictureController else { return }
        starting = true
        report("starting")
        updateSource()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard controller === pictureInPictureController else { return }
        backgroundPreparation?.cancel()
        backgroundPreparation = nil
        starting = false
        activeStart = CACurrentMediaTime()
        frames = 0
        report("active")
        updateSource()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        guard controller === pictureInPictureController else { return }
        backgroundPreparation?.cancel()
        backgroundPreparation = nil
        starting = false
        dismissed = !foreground
        NSLog("Remote PiP start failed: %@", error.localizedDescription)
        report("failed")
        updateSource()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard controller === pictureInPictureController else { return }
        starting = false
        dismissed = !foreground
        paused = false
        if let start = activeStart {
            let elapsed = CACurrentMediaTime() - start
            NSLog("Remote PiP displayed %d frames in %.2f s (%.1f fps)", frames, elapsed, Double(frames) / max(elapsed, 0.001))
        }
        activeStart = nil
        report(restoringUI ? "restored" : "stopped")
        restoringUI = false
        updateSource()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        restoringUI = controller === pictureInPictureController && owner != nil && host?.viewIfLoaded?.window != nil
        completionHandler(restoringUI)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        guard controller === pictureInPictureController else { return }
        paused = !playing
        pictureInPictureController.invalidatePlaybackState()
        report(playing ? (live ? "active" : "disconnected") : "paused")
        updateSource()
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        paused || !live
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
