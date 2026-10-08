import Flutter
import Security
import UIKit

public final class IosEnhancements: NSObject {
    private let queue = DispatchQueue(label: "rustdesk.embedded-tailnet")
    private weak var controller: FlutterViewController?
    private var channel: FlutterMethodChannel?

    public init(controller: FlutterViewController) {
        self.controller = controller
        super.init()
        let channel = FlutterMethodChannel(name: "rustdesk/ios-enhancements", binaryMessenger: controller.binaryMessenger)
        self.channel = channel
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(FlutterError(code: "unavailable", message: "iOS integration is unavailable", details: nil)); return }
            if call.method == "isTablet" { result(UIDevice.current.userInterfaceIdiom == .pad); return }
            if call.method == "orientation" { self.rotate(call.arguments as? String ?? "system", result); return }
            self.queue.async {
                do {
                    let value = try self.tailnet(call)
                    DispatchQueue.main.async { result(value) }
                } catch {
                    DispatchQueue.main.async { result(FlutterError(code: "tailnet", message: error.localizedDescription, details: nil)) }
                }
            }
        }
    }

    private func rotate(_ mode: String, _ result: @escaping FlutterResult) {
        guard let controller = controller, let scene = controller.view.window?.windowScene else {
            result(FlutterError(code: "orientation", message: "The app window is not active. Try rotating again.", details: nil)); return
        }
        if mode == "system" { result(nil); return }
        let mask: UIInterfaceOrientationMask = mode == "landscape" ? .landscape : .portrait
        var completed = false
        func finish(_ error: String?) {
            guard !completed else { return }
            completed = true
            result(error.map { FlutterError(code: "orientation", message: $0, details: nil) })
        }
        if #available(iOS 16.0, *) {
            controller.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in
                finish("iOS refused the rotation. Use Rotate screen again, or unlock orientation in Control Center.")
            }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
        // A successful request has no completion callback. Verify the actual scene.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let accepted = mode == "landscape" ? scene.interfaceOrientation.isLandscape : scene.interfaceOrientation.isPortrait
            finish(accepted ? nil : "iOS did not rotate the window. Unlock orientation in Control Center, then use Rotate screen.")
        }
    }

    private func tailnet(_ call: FlutterMethodCall) throws -> Any? {
        switch call.method {
        case "tailnetStart":
            guard let config = call.arguments as? String else { throw failure("Invalid Tailnet configuration") }
            var directory = try stateDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let key = try stateKey(directory)
            let error = key.withUnsafeBytes { bytes in
                rd_tailnet_start(directory.path, config, bytes.bindMemory(to: UInt8.self).baseAddress, Int32(key.count))
            }
            try check(error)
            return nil
        case "tailnetStop":
            try check(rd_tailnet_stop()); return nil
        case "tailnetStatus":
            guard let value = rd_tailnet_status() else { throw failure("No Tailnet status") }
            defer { rd_tailnet_free(value) }
            return String(cString: value)
        case "tailnetForget":
            try check(rd_tailnet_stop())
            let directory = try stateDirectory()
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            let status = SecItemDelete(keyQuery() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure("Could not remove the Tailnet key from Keychain") }
            return nil
        default: return FlutterMethodNotImplemented
        }
    }

    private func stateDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("embedded-tailnet", isDirectory: true)
    }
    private func keyQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "rustdesk") + ".embedded-tailnet",
         kSecAttrAccount as String: "state-encryption-key"]
    }
    private func stateKey(_ directory: URL) throws -> Data {
        var query = keyQuery()
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 { return data }
        guard status == errSecItemNotFound else { throw failure("Tailnet Keychain key is unavailable") }
        let identity = directory.appendingPathComponent("identity")
        if FileManager.default.fileExists(atPath: identity.path),
           !(try FileManager.default.contentsOfDirectory(atPath: identity.path)).isEmpty {
            throw failure("The saved identity has no Keychain key. Clear the local identity to authorize a new node.")
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw failure("Could not create a secure state key") }
        let data = Data(bytes)
        var entry = keyQuery()
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw failure("Could not save the Tailnet key in Keychain") }
        return data
    }
    private func check(_ message: UnsafeMutablePointer<CChar>?) throws {
        if let message = message {
            defer { rd_tailnet_free(message) }
            throw failure(String(cString: message))
        }
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "RustDesk.Tailnet", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
