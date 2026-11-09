import Foundation
import IOKit.pwr_mgt
import UserNotifications

/// Keeps the Mac awake while transfers are active.
final class SleepGuard {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isHolding = false

    func update(shouldHold: Bool) {
        if shouldHold && !isHolding {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Peerbloom is transferring files" as CFString,
                &assertionID)
            isHolding = result == kIOReturnSuccess
        } else if !shouldHold && isHolding {
            IOPMAssertionRelease(assertionID)
            isHolding = false
        }
    }

    deinit { update(shouldHold: false) }
}

/// Posts user notifications. Only works when running as a bundled .app.
enum Notifier {
    private static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum DiskSpace {
    /// Free bytes on the volume holding `path` (or its nearest existing parent).
    static func available(at path: String) -> Int64? {
        var url = URL(fileURLWithPath: path)
        while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" {
            url.deleteLastPathComponent()
        }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// Downloads and parses IP blocklists in the common P2P ("name:1.2.3.4-1.2.3.9") and
/// eMule DAT ("1.2.3.4 - 1.2.3.9 , 000 , name") plain-text formats.
enum Blocklist {
    static func parse(_ text: String) -> [(String, String)] {
        var ranges: [(String, String)] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            var rangePart = Substring(line)
            if let comma = line.firstIndex(of: ",") {
                rangePart = line[..<comma]                       // DAT
            } else if let colon = line.lastIndex(of: ":"), line[line.index(after: colon)...].contains("-") {
                rangePart = line[line.index(after: colon)...]    // P2P
            }
            let parts = rangePart.split(separator: "-", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, isIPv4(parts[0]), isIPv4(parts[1]) else { continue }
            ranges.append((normalize(parts[0]), normalize(parts[1])))
        }
        return ranges
    }

    private static func isIPv4(_ s: String) -> Bool {
        let octets = s.split(separator: ".")
        return octets.count == 4 && octets.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    /// DAT files pad octets with zeros ("001.002.003.004").
    private static func normalize(_ s: String) -> String {
        s.split(separator: ".").map { String(Int($0) ?? 0) }.joined(separator: ".")
    }

    static func download(from urlString: String) async throws -> [(String, String)] {
        guard let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw URLError(.cannotDecodeContentData)
        }
        return parse(text)
    }
}
