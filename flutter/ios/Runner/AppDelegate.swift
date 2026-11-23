import UIKit
import Flutter
import IosEnhancements
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var enhancements: IosEnhancements?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      // Mix remote audio with other apps while still respecting silent mode.
      try AVAudioSession.sharedInstance().setCategory(.ambient)
    } catch {
      NSLog("Failed to configure audio mixing: %@", error.localizedDescription)
    }
    dummyMethodToEnforceBundling();
    rd_ios_pip_register_frame_sink { display, bytes, width, height, stride in
      IosEnhancements.submitPictureInPictureFrame(display, bytes, width, height, stride)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func sceneForegroundChanged(_ foreground: Bool) {
    enhancements?.sceneForegroundChanged(foreground)
  }

  // With the UIScene life cycle, the FlutterViewController only exists once the scene
  // connects, and FlutterAppDelegate reaches its engine through `window`. A launch URL
  // also arrives with the scene instead of in launchOptions, so forward it to plugins here.
  func sceneWillConnect(window: UIWindow?, launchURL: URL?) {
    self.window = window
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      enhancements = IosEnhancements(controller: controller)
    }
    var launchOptions: [UIApplication.LaunchOptionsKey: Any] = [:]
    if let launchURL = launchURL {
      launchOptions[.url] = launchURL
    }
    _ = super.application(UIApplication.shared, didFinishLaunchingWithOptions: launchOptions)
  }
    
  public func dummyMethodToEnforceBundling() {
      dummy_method_to_enforce_bundling();
    session_get_rgba(nil, 0);
  }
}
