import CoreServices
import Foundation

/// Marks downloaded files as coming from the internet, the same mark Safari puts on its downloads, so
/// Gatekeeper checks apps and installers before they open. Videos, music and documents open as usual.
///
/// This is done explicitly when a transfer finishes. `LSFileQuarantineEnabled` in Info.plist doesn't
/// mark files written by apps outside the App Sandbox.
enum Quarantine {
    /// Marks each file, and every folder between it and `root`, so app bundles (folders) are covered too.
    static func mark(_ relativePaths: [String], in root: URL) {
        var done: Set<String> = []
        for path in relativePaths {
            var url = root.appendingPathComponent(path)
            while url.path.hasPrefix(root.path + "/"), done.insert(url.path).inserted {
                mark(url)
                url = url.deletingLastPathComponent()
            }
        }
    }

    static func mark(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var target = url
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "Peerbloom",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
        ]
        try? target.setResourceValues(values)
    }

    static func isMarked(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) > 0
    }
}
