import XCTest
@testable import Peerbloom

final class FormattingTests: XCTestCase {
    func testETA() {
        XCTAssertEqual(Format.eta(nil), "—")
        XCTAssertEqual(Format.eta(42), "42s")
        XCTAssertEqual(Format.eta(134), "2m 14s")
        XCTAssertEqual(Format.eta(3 * 3600 + 120), "3h 2m")
        XCTAssertEqual(Format.eta(2 * 86_400 + 3600), "2d 1h")
    }

    func testPercent() {
        XCTAssertEqual(Format.percent(0.05), "5.0%")
        XCTAssertEqual(Format.percent(0.62), "62%")
        XCTAssertEqual(Format.percent(1), "100%")
    }

    func testRateShowsDashWhenIdle() {
        XCTAssertEqual(Format.rate(0), "—")
    }
}

final class BlocklistTests: XCTestCase {
    func testParsesP2PAndDATFormats() {
        let text = """
        # comment
        Some Org:1.2.3.0-1.2.3.255
        001.002.004.000 - 001.002.004.255 , 000 , Other Org
        not a range
        300.1.1.1-300.1.1.2
        """
        let ranges = Blocklist.parse(text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].0, "1.2.3.0")
        XCTAssertEqual(ranges[0].1, "1.2.3.255")
        XCTAssertEqual(ranges[1].0, "1.2.4.0")
        XCTAssertEqual(ranges[1].1, "1.2.4.255")
    }
}

final class ScheduleTests: XCTestCase {
    private func date(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        // 2026-10-11 is a Sunday (weekday 1).
        var c = DateComponents(year: 2026, month: 10, day: 10 + weekday, hour: hour, minute: minute)
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func testDaytimeWindow() {
        var p = Preferences()
        p.scheduleEnabled = true
        p.scheduleStart = 9 * 60
        p.scheduleEnd = 18 * 60
        p.scheduleDays = [2] // Monday
        XCTAssertTrue(p.altSpeedActive(at: date(weekday: 2, hour: 10), calendar: utc))
        XCTAssertFalse(p.altSpeedActive(at: date(weekday: 2, hour: 19), calendar: utc))
        XCTAssertFalse(p.altSpeedActive(at: date(weekday: 3, hour: 10), calendar: utc))
    }

    func testOvernightWindow() {
        var p = Preferences()
        p.scheduleEnabled = true
        p.scheduleStart = 22 * 60
        p.scheduleEnd = 6 * 60
        p.scheduleDays = Set(1...7)
        XCTAssertTrue(p.altSpeedActive(at: date(weekday: 4, hour: 23), calendar: utc))
        XCTAssertTrue(p.altSpeedActive(at: date(weekday: 4, hour: 5), calendar: utc))
        XCTAssertFalse(p.altSpeedActive(at: date(weekday: 4, hour: 12), calendar: utc))
    }

    func testManualOverride() {
        var p = Preferences()
        p.altSpeedManual = true
        XCTAssertTrue(p.altSpeedActive())
    }
}

final class FilterTests: XCTestCase {
    func testStatusFilters() {
        let t = Transfer(id: "a", name: "x", savePath: "/", state: .queued, isPaused: false, sequential: false,
                         hasMetadata: true, progress: 0.1, totalWanted: 10, totalDone: 1, uploaded: 0,
                         downloaded: 1, downloadRate: 0, uploadRate: 0, peers: 0, seeds: 0, knownPeers: 0,
                         knownSeeds: 0, availability: 0, queuePosition: 0, addedDate: Date(),
                         completedDate: nil, errorMessage: nil)
        XCTAssertTrue(StatusFilter.pausedQueued.matches(t))
        XCTAssertFalse(StatusFilter.downloading.matches(t))
        XCTAssertTrue(StatusFilter.all.matches(t))
    }

    func testOnlyTunnelsCountAsVPN() {
        XCTAssertFalse(NetworkInterface(name: "en0", addresses: ["192.168.1.20"], isUp: true).looksLikeVPN)
        XCTAssertTrue(NetworkInterface(name: "utun4", addresses: ["10.5.0.2"], isUp: true).looksLikeVPN)
        XCTAssertTrue(NetworkInterface(name: "wg0", addresses: ["10.2.0.2"], isUp: true).looksLikeVPN)
        // macOS keeps idle utun interfaces with only a link-local address for its own services.
        XCTAssertFalse(NetworkInterface(name: "utun0", addresses: ["fe80::1"], isUp: true).looksLikeVPN)
    }

    func testOnlyConnectedInterfacesAreOffered() {
        XCTAssertTrue(NetworkInterface(name: "en0", addresses: ["192.168.1.20"], isUp: true).isActiveConnection)
        XCTAssertFalse(NetworkInterface(name: "en1", addresses: ["fe80::1"], isUp: true).isActiveConnection)
        XCTAssertFalse(NetworkInterface(name: "en0", addresses: ["192.168.1.20"], isUp: false).isActiveConnection)
        XCTAssertFalse(NetworkInterface(name: "utun4", addresses: ["10.5.0.2"], isUp: false).isActiveVPN)
        XCTAssertFalse(NetworkInterface(name: "awdl0", addresses: ["fe80::2"], isUp: true).isActiveConnection)
    }

    func testAnyVPNFollowsTheTunnel() {
        var prefs = Preferences()
        prefs.boundInterface = Preferences.anyVPN
        let wifi = NetworkInterface(name: "en0", addresses: ["192.168.1.20"], isUp: true)
        let tunnel = NetworkInterface(name: "utun5", addresses: ["10.5.0.2"], isUp: true)
        XCTAssertEqual(TorrentEngine.boundInterface(for: prefs, interfaces: [wifi, tunnel]), "utun5")
        // With no VPN up, bind to loopback so nothing leaves the Mac.
        XCTAssertEqual(TorrentEngine.boundInterface(for: prefs, interfaces: [wifi]), "lo0")
        prefs.boundInterface = "en0"
        XCTAssertEqual(TorrentEngine.boundInterface(for: prefs, interfaces: [wifi, tunnel]), "en0")
        prefs.boundInterface = nil
        XCTAssertNil(TorrentEngine.boundInterface(for: prefs, interfaces: [wifi, tunnel]))
    }

    func testVPNAppNames() {
        XCTAssertTrue(VPNApps.isVPNAppName("NordVPN"))
        XCTAssertTrue(VPNApps.isVPNAppName("Proton VPN"))
        XCTAssertTrue(VPNApps.isVPNAppName("Tunnelblick"))
        XCTAssertFalse(VPNApps.isVPNAppName("Safari"))
    }

    func testOlderSavedPreferencesStillDecode() throws {
        // Settings saved before newer options existed keep their values; the new options get defaults.
        var old = Preferences()
        old.listenPort = 6000
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        for key in ["privacyMode", "proxyType", "themeID", "vpnAppPath"] { json.removeValue(forKey: key) }
        let prefs = Preferences.decode(try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(prefs.listenPort, 6000)
        XCTAssertFalse(prefs.privacyMode)
        XCTAssertEqual(prefs.themeID, AppTheme.standard.id)
    }

    func testRiskyFiles() {
        XCTAssertNil(RiskyFiles.risk(of: "Sintel/sintel-4k.mkv"))
        XCTAssertNil(RiskyFiles.risk(of: "ubuntu-26.04-desktop-amd64.iso"))
        XCTAssertEqual(RiskyFiles.risk(of: "Tool/setup.exe"), .program)
        XCTAssertEqual(RiskyFiles.risk(of: "Installer.pkg"), .program)
        XCTAssertEqual(RiskyFiles.risk(of: "Movie (2024)/Movie.mp4.exe"), .disguised)
        XCTAssertEqual(RiskyFiles.risk(of: "Movie.mp4          .scr"), .disguised)
        XCTAssertEqual(RiskyFiles.risk(of: "evil\u{202E}4pm.exe"), .disguised)
        XCTAssertEqual(RiskyFiles.risk(of: "Cool.app/Contents/MacOS/Cool"), .program)
    }

    func testAppBundleCountsAsOneFinding() {
        let files = [
            FileItem(index: 0, path: "Pack/Cool.app/Contents/MacOS/Cool", size: 10, downloaded: 0, priority: .normal),
            FileItem(index: 1, path: "Pack/Cool.app/Contents/Info.plist", size: 10, downloaded: 0, priority: .normal),
            FileItem(index: 2, path: "Pack/readme.txt", size: 10, downloaded: 0, priority: .normal),
        ]
        let findings = RiskyFiles.check(files)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.path, "Pack/Cool.app")
        XCTAssertEqual(findings.first?.indices, [0, 1])
    }

    func testQuarantineMarksFilesAndAppBundles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = root.appendingPathComponent("Pack/Cool.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: bundle.appendingPathComponent("Cool"))
        try Data("x".utf8).write(to: root.appendingPathComponent("Pack/readme.txt"))
        defer { try? FileManager.default.removeItem(at: root) }

        Quarantine.mark(["Pack/Cool.app/Contents/MacOS/Cool", "Pack/readme.txt"], in: root)

        XCTAssertTrue(Quarantine.isMarked(bundle.appendingPathComponent("Cool")))
        XCTAssertTrue(Quarantine.isMarked(root.appendingPathComponent("Pack/Cool.app")))
        XCTAssertTrue(Quarantine.isMarked(root.appendingPathComponent("Pack/readme.txt")))
        XCTAssertFalse(Quarantine.isMarked(root), "the save folder itself is left alone")
    }

    func testPrivacyModeOverridesSettings() {
        var prefs = Preferences()
        prefs.encryption = .allow
        prefs.enableLSD = true
        prefs.enablePortMapping = true
        prefs.privacyMode = true
        XCTAssertEqual(prefs.effectiveEncryption, .require)
        XCTAssertTrue(prefs.effectiveAnonymousMode)
        XCTAssertFalse(prefs.effectiveLSD)
        XCTAssertFalse(prefs.effectivePortMapping)
        XCTAssertEqual(prefs.effectiveBinding, Preferences.anyVPN, "without a proxy, traffic must stay on a VPN")

        // A SOCKS5 proxy carrying peer traffic hides the address, so the VPN isn't required.
        prefs.proxyType = .socks5
        prefs.proxyHost = "proxy.example.com"
        XCTAssertNil(prefs.effectiveBinding)
        // An HTTP proxy can't carry DHT or uTP, so it doesn't count.
        prefs.proxyType = .http
        XCTAssertEqual(prefs.effectiveBinding, Preferences.anyVPN)

        prefs.privacyMode = false
        XCTAssertEqual(prefs.effectiveEncryption, .allow)
        XCTAssertNil(prefs.effectiveBinding)
    }

    func testBuiltInThemesPassTheirOwnChecks() throws {
        for theme in AppTheme.builtIns {
            XCTAssertNoThrow(try theme.validate(), theme.name)
        }
        XCTAssertEqual(Set(AppTheme.builtIns.map(\.id)).count, AppTheme.builtIns.count)
    }

    func testExampleThemeFileLoads() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Themes/Examples/night-swim.peerbloomtheme")
        let theme = try AppTheme.load(from: Data(contentsOf: url))
        XCTAssertEqual(theme.name, "Night Swim")
        XCTAssertEqual(theme.font, .rounded)
    }

    func testThemeChecks() {
        func theme(format: Int = 1, appearance: String = "dark", download: Any, background: String? = nil) -> Result<AppTheme, Error> {
            var colors: [String: Any] = ["accent": "#3C8DFF", "seeding": "#2DE1C2", "protected": "#7EE2A8",
                                         "warning": "#F5B04A", "download": download]
            if let background { colors["background"] = background }
            let json: [String: Any] = ["format": format, "name": "Test", "appearance": appearance, "colors": colors]
            return Result { try AppTheme.load(from: JSONSerialization.data(withJSONObject: json)) }
        }

        // Light/dark pairs and single colours both work.
        XCTAssertNoThrow(try theme(download: ["light": "#0A64D6", "dark": "#4C9EFF"]).get())
        XCTAssertNoThrow(try theme(download: "#4C9EFF").get())

        // A theme that follows the Mac's setting is checked in light mode too: these bright colours are
        // unreadable on a white window.
        XCTAssertThrowsError(try theme(appearance: "system", download: "#4C9EFF").get()) { error in
            guard case ThemeError.lowContrast = error else { return XCTFail("\(error)") }
        }

        // Dark blue on a dark background is unreadable.
        XCTAssertThrowsError(try theme(download: "#101830", background: "#0B1A2E").get()) { error in
            guard case ThemeError.lowContrast("download", _) = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try theme(download: "blue").get()) { XCTAssertEqual($0 as? ThemeError, .badColor("download")) }
        XCTAssertThrowsError(try theme(format: 2, download: "#4C9EFF").get()) {
            XCTAssertEqual($0 as? ThemeError, .unsupportedFormat(2))
        }
        XCTAssertThrowsError(try AppTheme.load(from: Data("not json".utf8))) { XCTAssertEqual($0 as? ThemeError, .unreadable) }
        XCTAssertThrowsError(try AppTheme.load(from: Data(count: AppTheme.maxFileSize + 1))) {
            XCTAssertEqual($0 as? ThemeError, .tooLarge)
        }
    }

    func testThemeTextVariantMatchesTheOriginalDesign() {
        // The standard theme's text colours stay close to the hand-picked originals (#0A4FA8 / #8EC1FF).
        let text = AppTheme.standard.colors.download.textVariant
        XCTAssertLessThan(RGB(hex: text.light)!.contrast(with: RGB(hex: "#0A4FA8")!), 1.1)
        XCTAssertLessThan(RGB(hex: text.dark)!.contrast(with: RGB(hex: "#8EC1FF")!), 1.1)
    }
}
