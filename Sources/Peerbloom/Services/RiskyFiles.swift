import Foundation

/// Spots files in a torrent that could harm the Mac: apps, installers and scripts, and files dressed up
/// as something harmless ("movie.mp4.exe"). Movies, music and documents never need to be programs,
/// so these are the classic way torrents carry malware.
enum RiskyFiles {
    enum Risk: Equatable {
        case program     // an app, installer or script
        case disguised   // a program pretending to be a video, song or document
    }

    struct Finding: Identifiable, Equatable {
        var id: String { path }
        /// The file, or the app or installer bundle it sits in.
        let path: String
        /// Every file index it covers, so all of them can be skipped.
        let indices: [Int]
        let risk: Risk
        var name: String { (path as NSString).lastPathComponent }
    }

    /// Mac bundles are folders, so they show up as a folder somewhere in a file's path ("Foo.app/Contents/…").
    private static let bundleExtensions: Set<String> = ["app", "pkg", "mpkg", "workflow", "prefpane", "saver", "kext"]

    /// Files that run code when opened, on the Mac or on Windows.
    private static let programExtensions: Set<String> = [
        // Mac
        "app", "pkg", "mpkg", "dmg", "command", "tool", "terminal", "scpt", "applescript", "workflow",
        "sh", "zsh", "bash", "csh", "jar", "dylib", "kext",
        // Windows
        "exe", "msi", "bat", "cmd", "com", "scr", "pif", "vbs", "vbe", "ps1", "lnk", "hta", "wsf", "jse", "cpl", "reg",
    ]

    /// Extensions a disguised program pretends to have.
    private static let harmlessLooking: Set<String> = [
        "mp4", "mkv", "avi", "mov", "m4v", "wmv", "webm", "mp3", "flac", "m4a", "wav", "aac", "ogg",
        "pdf", "epub", "txt", "doc", "docx", "jpg", "jpeg", "png", "gif", "srt", "iso", "zip",
    ]

    /// Risky files in a torrent, with everything inside one app bundle grouped as a single finding.
    static func check(_ files: [FileItem]) -> [Finding] {
        var order: [String] = []
        var grouped: [String: (indices: [Int], risk: Risk)] = [:]
        for file in files {
            guard let (risk, shown) = classify(file.path) else { continue }
            if grouped[shown] == nil { order.append(shown) }
            grouped[shown, default: ([], risk)].indices.append(file.index)
        }
        return order.map { Finding(path: $0, indices: grouped[$0]!.indices, risk: grouped[$0]!.risk) }
    }

    static func risk(of path: String) -> Risk? { classify(path)?.risk }

    /// The risk, and the path to show: the file itself, or the bundle it's inside.
    private static func classify(_ path: String) -> (risk: Risk, shown: String)? {
        let components = path.split(separator: "/").map(String.init)
        guard let name = components.last else { return nil }
        // Right-to-left override characters can make "evil\u{202E}4pm.exe" display as "evilexe.mp4".
        if name.unicodeScalars.contains(where: { (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }) {
            return (.disguised, path)
        }
        if let bundle = components.dropLast().firstIndex(where: { bundleExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            return (.program, components[...bundle].joined(separator: "/"))
        }
        let ext = (name as NSString).pathExtension.lowercased()
        guard programExtensions.contains(ext) else { return nil }
        let stem = (name as NSString).deletingPathExtension
        let innerExt = (stem as NSString).pathExtension.lowercased().trimmingCharacters(in: .whitespaces)
        // "movie.mp4.exe", or a long run of spaces hiding the real extension: "movie.mp4        .exe".
        if harmlessLooking.contains(innerExt) || stem.hasSuffix("   ") {
            return (.disguised, path)
        }
        return (.program, path)
    }

    /// A one-line summary for alerts and banners.
    static func summary(_ findings: [Finding]) -> String {
        let disguised = findings.filter { $0.risk == .disguised }.count
        if disguised > 0 {
            return disguised == 1
                ? "One file pretends to be something harmless but is actually a program."
                : "\(disguised) files pretend to be something harmless but are actually programs."
        }
        return findings.count == 1
            ? "It contains an app, installer or script."
            : "It contains \(findings.count) apps, installers or scripts."
    }
}
