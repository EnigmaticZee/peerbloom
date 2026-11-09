import Foundation

enum EncryptionMode: String, Codable, CaseIterable, Identifiable {
    case require, prefer, allow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .require: "Require"
        case .prefer: "Prefer"
        case .allow: "Allow"
        }
    }
}

enum ProxyType: String, Codable, CaseIterable, Identifiable {
    case none, socks5, http
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "None"
        case .socks5: "SOCKS5"
        case .http: "HTTP"
        }
    }
}

enum RowDensity: String, Codable, CaseIterable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Everything the user can change in Settings. Stored as JSON in UserDefaults.
struct Preferences: Codable, Equatable {
    // General
    var defaultSavePath = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Peerbloom").path) ?? NSHomeDirectory() + "/Downloads/Peerbloom"
    var startImmediately = true
    var notifyOnFinish = true
    var preventSleep = true
    var showMenuBarIcon = true
    var rowDensity = RowDensity.comfortable
    var themeID = AppTheme.standard.id
    var minFreeSpaceGB = 10
    var activeDownloads = 3
    var activeSeeds = 5

    // Network & privacy
    var listenPort = 51413
    /// An interface name, `Preferences.anyVPN`, or nil for no binding.
    var boundInterface: String?
    var killSwitch = true
    /// The VPN app to offer to open when the VPN is off. Nil picks the first one installed.
    var vpnAppPath: String?
    var encryption = EncryptionMode.prefer
    var anonymousMode = false
    var enableDHT = true
    var enableLSD = true
    var enablePortMapping = true
    var blocklistEnabled = false
    var blocklistURL = ""
    /// One switch for the strictest settings: VPN or proxy only, encryption required, anonymous mode,
    /// and no local network broadcasts or router port opening. See `effective…` below.
    var privacyMode = false

    // Proxy. The password lives in the Keychain (`Keychain.proxyPassword`).
    var proxyType = ProxyType.none
    var proxyHost = ""
    var proxyPort = 1080
    var proxyUsername = ""
    var proxyPeerConnections = true
    var proxyTrackerConnections = true

    // Speed (KB/s, 0 = unlimited)
    var downloadLimitKB = 0
    var uploadLimitKB = 0
    var altDownloadLimitKB = 1024
    var altUploadLimitKB = 256
    var altSpeedManual = false
    var scheduleEnabled = false
    /// Minutes after midnight.
    var scheduleStart = 9 * 60
    var scheduleEnd = 18 * 60
    /// Calendar weekday numbers, 1 = Sunday.
    var scheduleDays: Set<Int> = [2, 3, 4, 5, 6]

    /// Stored in `boundInterface` to follow whichever VPN tunnel is up. VPN apps can get a new tunnel name
    /// on each reconnect (utun4, then utun5), so binding to a fixed name isn't enough. Kept as a string so
    /// settings saved by older versions still decode.
    static let anyVPN = "*vpn"

    var bindsToVPN: Bool {
        guard let iface = effectiveBinding else { return false }
        return iface == Self.anyVPN || NetworkInterface.isTunnelName(iface)
    }

    /// A SOCKS5 proxy is set up and carries peer traffic, so peers see the proxy's address. HTTP proxies don't
    /// count: they can't carry UDP (DHT, uTP, UDP trackers), which would then go out over the normal connection.
    var proxyCoversPeers: Bool {
        proxyType == .socks5 && !proxyHost.trimmingCharacters(in: .whitespaces).isEmpty && proxyPeerConnections
    }

    // Settings as Privacy mode overrides them. The engine and status checks use these.
    /// Privacy mode keeps traffic on a VPN unless a proxy already hides the address.
    var effectiveBinding: String? { privacyMode && !proxyCoversPeers ? Self.anyVPN : boundInterface }
    var effectiveEncryption: EncryptionMode { privacyMode ? .require : encryption }
    var effectiveAnonymousMode: Bool { privacyMode || anonymousMode }
    var effectiveLSD: Bool { privacyMode ? false : enableLSD }
    var effectivePortMapping: Bool { privacyMode ? false : enablePortMapping }

    private static let key = "preferences.v1"

    static func load() -> Preferences {
        UserDefaults.standard.data(forKey: key).map(decode) ?? Preferences()
    }

    /// Decodes saved settings over the defaults, so settings added in a newer version get their default
    /// instead of making the whole saved file unreadable.
    static func decode(_ data: Data) -> Preferences {
        guard let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(Preferences()),
              let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: defaults.merging(saved) { _, new in new }),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: merged) else {
            return Preferences()
        }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// True when the alternative (slower) limits should be in effect right now.
    func altSpeedActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        if altSpeedManual { return true }
        guard scheduleEnabled else { return false }
        let weekday = calendar.component(.weekday, from: date)
        guard scheduleDays.contains(weekday) else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if scheduleStart <= scheduleEnd {
            return minutes >= scheduleStart && minutes < scheduleEnd
        }
        // Window crosses midnight, e.g. 22:00–06:00.
        return minutes >= scheduleStart || minutes < scheduleEnd
    }
}
