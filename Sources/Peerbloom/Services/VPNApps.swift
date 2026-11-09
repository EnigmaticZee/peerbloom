import AppKit

/// Finds the VPN apps the user has installed, so Peerbloom can offer to open theirs when the VPN is off.
/// Peerbloom never controls a VPN; it only opens the app so the user can connect.
enum VPNApps {
    struct App: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    /// Well-known VPN apps whose names don't contain "VPN".
    private static let knownNames: Set<String> = [
        "Tunnelblick", "WireGuard", "Surfshark", "Windscribe", "TunnelBear", "Viscosity",
        "Cloudflare WARP", "Private Internet Access", "Mullvad",
    ]

    static func isVPNAppName(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("vpn") || knownNames.contains(name)
    }

    /// VPN apps in /Applications and ~/Applications, sorted by name.
    static func installed() -> [App] {
        let fm = FileManager.default
        let folders = [URL(fileURLWithPath: "/Applications"),
                       fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [App] = []
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" && isVPNAppName(url.deletingPathExtension().lastPathComponent) {
                found.append(App(url: url))
            }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func open(_ app: App) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }
}
