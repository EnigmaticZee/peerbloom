import AppKit
import Foundation
import Observation

/// What the Add sheet is adding.
enum AddSource: Identifiable {
    case magnet(String)
    case file(TorrentPreview)

    var id: String {
        switch self {
        case .magnet(let uri): uri
        case .file(let p): p.path
        }
    }
}

@MainActor
@Observable
final class AppStore {
    /// One store (and one libtorrent session) for the whole app.
    static let shared = AppStore()

    // MARK: State the UI reads

    private(set) var transfers: [Transfer] = []
    private(set) var session = SessionInfo()
    private(set) var detail: TransferDetail?
    private(set) var history: [String: [SpeedSample]] = [:]
    private(set) var totalHistory: [SpeedSample] = []
    private(set) var vpnStatus: VPNStatus = .notBound
    /// The VPN tunnel that is connected right now, whether or not Peerbloom is bound to it.
    private(set) var detectedVPN: String?
    private(set) var installedVPNApps: [VPNApps.App] = []
    /// The address peers and trackers report seeing for us. With a working VPN or proxy it's theirs, not the
    /// home connection's. Learned from the swarm itself, so no outside "what's my IP" service is contacted.
    private(set) var publicAddress: String?
    private(set) var freeSpace: Int64?
    private(set) var altSpeedActive = false
    private(set) var blocklistRuleCount = 0
    private(set) var blocklistUpdated: Date?

    var sidebar: SidebarSelection = .status(.all)
    var selection: Set<String> = []
    var searchText = ""
    var sortOrder: [KeyPathComparator<Transfer>] = [KeyPathComparator(\.addedDate, order: .reverse)]
    var pendingAdd: AddSource?
    var pendingRemoval: [String]?
    var errorMessage: String?
    /// Magnet transfers whose file list turned out to contain programs, waiting for the user to decide.
    var riskyAlerts: [RiskyAlert] = []

    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save()
            applyPreferences(previous: oldValue)
        }
    }

    var tags: [Tag] { didSet { saveTags() } }
    private(set) var tagAssignments: [String: UUID] = [:] { didSet { saveTags() } }

    // MARK: Internals

    private let engine: TorrentEngine
    private let stateDirectory: URL
    private var timer: Timer?
    private var sampleCounter = 0
    private var tickCount = 0
    private var knownCompleted: Set<String>?
    private var killSwitchPaused: Set<String> = []
    private var diskGuardPaused: Set<String> = []
    private let sleepGuard = SleepGuard()
    private var detailRequestInFlight = false
    private static let historyLength = 300 // 5 minutes at one sample per second

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        stateDirectory = support.appendingPathComponent("Peerbloom", isDirectory: true)
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)

        let prefs = Preferences.load()
        preferences = prefs
        let saved = Self.loadTags(from: stateDirectory)
        tags = saved.tags.isEmpty ? Self.defaultTags : saved.tags
        tagAssignments = saved.assignments
        try? FileManager.default.createDirectory(atPath: prefs.defaultSavePath, withIntermediateDirectories: true)

        engine = TorrentEngine(preferences: prefs, stateDirectory: stateDirectory.appendingPathComponent("state"))
        altSpeedActive = prefs.altSpeedActive()
        if altSpeedActive { engine.apply(prefs, altSpeed: true) }
        Notifier.requestPermission()
        loadCachedBlocklist()
        installedVPNApps = VPNApps.installed()
        DispatchQueue.main.async { ThemeLibrary.shared.applyAppearance(of: Theme.current) }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    // MARK: Derived values

    var visibleTransfers: [Transfer] {
        var list = transfers
        switch sidebar {
        case .status(let f): list = list.filter(f.matches)
        case .tag(let id): list = list.filter { tagAssignments[$0.id] == id }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return list.sorted(using: sortOrder)
    }

    var focused: Transfer? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return transfers.first { $0.id == id }
    }

    func count(_ filter: StatusFilter) -> Int { transfers.filter(filter.matches).count }
    func count(tag: Tag) -> Int { transfers.filter { tagAssignments[$0.id] == tag.id }.count }

    var totalDownloadRate: Int { transfers.reduce(0) { $0 + $1.downloadRate } }
    var totalUploadRate: Int { transfers.reduce(0) { $0 + $1.uploadRate } }

    var sessionRatio: Double {
        let down = transfers.reduce(Int64(0)) { $0 + $1.downloaded }
        let up = transfers.reduce(Int64(0)) { $0 + $1.uploaded }
        return down > 0 ? Double(up) / Double(down) : 0
    }

    func tag(for transferID: String) -> Tag? {
        tagAssignments[transferID].flatMap { id in tags.first { $0.id == id } }
    }

    var sidebarTitle: String {
        switch sidebar {
        case .status(let f): f.title
        case .tag(let id): tags.first { $0.id == id }?.name ?? "Tag"
        }
    }

    // MARK: Polling

    private func tick() {
        tickCount += 1
        engine.snapshot { [weak self] snap in self?.apply(snap) }
        if tickCount % 60 == 0 { installedVPNApps = VPNApps.installed() }
        if tickCount % 5 == 1 { checkVPN() }
        if tickCount % 10 == 1 { checkDiskSpace() }
        if tickCount % 30 == 1 { checkAltSpeed() }
        if tickCount % 300 == 0 { engine.saveState(timeout: 3, wait: false) }
        if tickCount % 3600 == 0 { refreshBlocklistIfStale() }
        refreshDetail()
    }

    private func apply(_ snap: TorrentEngine.Snapshot) {
        transfers = snap.transfers
        session = snap.session
        selection = selection.intersection(Set(transfers.map(\.id)))

        sampleCounter += 1
        let now = Date()
        for t in transfers {
            var h = history[t.id] ?? []
            h.append(SpeedSample(id: sampleCounter, time: now, down: t.downloadRate, up: t.uploadRate))
            if h.count > Self.historyLength { h.removeFirst(h.count - Self.historyLength) }
            history[t.id] = h
        }
        totalHistory.append(SpeedSample(id: sampleCounter, time: now, down: totalDownloadRate, up: totalUploadRate))
        if totalHistory.count > Self.historyLength { totalHistory.removeFirst() }

        // Only notify for transfers that finish while the app is running.
        let completedNow = Set(transfers.filter { $0.progress >= 1 }.map(\.id))
        if knownCompleted == nil { knownCompleted = completedNow }
        for event in snap.events where event.kind == .finished {
            if let hash = event.infoHash { quarantineFiles(hash) }
            guard let hash = event.infoHash, knownCompleted?.contains(hash) == false else { continue }
            knownCompleted?.insert(hash)
            if preferences.notifyOnFinish {
                Notifier.post(title: "Download complete", body: event.name ?? "A transfer finished.")
            }
        }
        for event in snap.events where event.kind == .externalAddress {
            publicAddress = event.message
        }
        for event in snap.events where event.kind == .metadataReceived {
            if let hash = event.infoHash { checkForPrograms(hash) }
        }
        for event in snap.events where event.kind == .torrentError {
            errorMessage = "\(event.name ?? "A transfer"): \(event.message)"
        }

        sleepGuard.update(shouldHold: preferences.preventSleep && transfers.contains { $0.state == .downloading })
    }

    private func refreshDetail() {
        guard let id = focused?.id, !detailRequestInFlight else {
            if focused == nil { detail = nil }
            return
        }
        detailRequestInFlight = true
        engine.detail(for: id, buckets: 256) { [weak self] d in
            guard let self else { return }
            self.detailRequestInFlight = false
            if self.focused?.id == id { self.detail = d }
        }
    }

    // MARK: Risky files

    /// Marks a finished transfer's files as downloaded, so Gatekeeper checks any apps among them before they open.
    private func quarantineFiles(_ hash: String) {
        guard let savePath = transfers.first(where: { $0.id == hash })?.savePath else { return }
        engine.detail(for: hash, buckets: 1) { detail in
            guard let paths = detail?.files.filter({ $0.priority != .skip }).map(\.path) else { return }
            DispatchQueue.global(qos: .utility).async {
                Quarantine.mark(paths, in: URL(fileURLWithPath: savePath))
            }
        }
    }

    /// A magnet link's file list only arrives after adding it, so its check happens here rather than in the Add sheet.
    private func checkForPrograms(_ hash: String) {
        engine.detail(for: hash, buckets: 1) { [weak self] detail in
            guard let self, let detail else { return }
            let findings = RiskyFiles.check(detail.files)
            guard !findings.isEmpty, !riskyAlerts.contains(where: { $0.id == hash }) else { return }
            let name = transfers.first { $0.id == hash }?.name ?? "A transfer"
            riskyAlerts.append(RiskyAlert(id: hash, name: name, findings: findings))
            if !NSApp.isActive {
                Notifier.post(title: "\(name) contains programs", body: RiskyFiles.summary(findings) + " Open Peerbloom to decide.")
            }
        }
    }

    /// Answers the oldest risky-files alert, skipping the programs or keeping them.
    func resolveRiskyAlert(skip: Bool) {
        guard !riskyAlerts.isEmpty else { return }
        let alert = riskyAlerts.removeFirst()
        guard skip else { return }
        for index in alert.findings.flatMap(\.indices) {
            setPriority(.skip, file: index, for: alert.id)
        }
    }

    // MARK: VPN binding and kill switch

    /// The VPN app to offer when the VPN is off: the one chosen in Settings, else the first one installed.
    var vpnApp: VPNApps.App? {
        if let path = preferences.vpnAppPath, FileManager.default.fileExists(atPath: path) {
            return VPNApps.App(url: URL(fileURLWithPath: path))
        }
        return installedVPNApps.first
    }

    func openVPNApp() {
        if let app = vpnApp { VPNApps.open(app) }
    }

    /// Saves the proxy password in the Keychain and applies it.
    func setProxyPassword(_ password: String) {
        Keychain.proxyPassword = password
        engine.apply(preferences, altSpeed: altSpeedActive)
    }

    /// Binds to whichever VPN is connected, now and after it reconnects.
    func bindToAnyVPN() {
        preferences.boundInterface = Preferences.anyVPN
    }

    private func checkVPN() {
        let interfaces = NetworkInterfaces.current()
        detectedVPN = NetworkInterfaces.activeVPN(in: interfaces)?.name
        guard let choice = preferences.effectiveBinding else {
            vpnStatus = .notBound
            releaseKillSwitch()
            return
        }
        if choice == Preferences.anyVPN {
            vpnStatus = detectedVPN.map { .protected($0) } ?? .waitingForVPN
            // A reconnect can bring the VPN back under a new name (utun4 → utun5), so rebind when it changes.
            if TorrentEngine.boundInterface(for: preferences, interfaces: interfaces) != engine.appliedInterface {
                engine.apply(preferences, altSpeed: altSpeedActive)
            }
        } else if let current = interfaces.first(where: { $0.name == choice }), current.isUp, !current.addresses.isEmpty {
            // Only a VPN tunnel counts as protected; Wi-Fi or Ethernet locks traffic but doesn't hide the IP.
            vpnStatus = current.looksLikeVPN ? .protected(choice) : .bound(choice)
        } else {
            vpnStatus = .down(choice)
        }
        switch vpnStatus {
        case .down(let iface): engageKillSwitch(title: "Connection lost", until: "\(iface) is back")
        case .waitingForVPN: engageKillSwitch(title: "No VPN connected", until: "a VPN connects")
        default: releaseKillSwitch()
        }
    }

    private func engageKillSwitch(title: String, until: String) {
        guard preferences.killSwitch, killSwitchPaused.isEmpty else { return }
        let running = transfers.filter { !$0.isPaused }.map(\.id)
        guard !running.isEmpty else { return }
        killSwitchPaused = Set(running)
        engine.pause(running)
        Notifier.post(title: title, body: "Peerbloom paused \(running.count) transfer(s) until \(until).")
    }

    private func releaseKillSwitch() {
        guard !killSwitchPaused.isEmpty else { return }
        engine.resume(Array(killSwitchPaused))
        killSwitchPaused = []
    }

    // MARK: Disk space guard

    private func checkDiskSpace() {
        freeSpace = DiskSpace.available(at: preferences.defaultSavePath)
        guard let free = freeSpace, preferences.minFreeSpaceGB > 0 else { return }
        let minimum = Int64(preferences.minFreeSpaceGB) * 1_000_000_000
        if free < minimum && diskGuardPaused.isEmpty {
            let downloading = transfers.filter { $0.state == .downloading || $0.state == .fetchingMetadata }.map(\.id)
            guard !downloading.isEmpty else { return }
            diskGuardPaused = Set(downloading)
            engine.pause(downloading)
            Notifier.post(title: "Low disk space",
                          body: "Peerbloom paused downloads. Less than \(preferences.minFreeSpaceGB) GB is free.")
        } else if free > minimum + 2_000_000_000 && !diskGuardPaused.isEmpty {
            engine.resume(Array(diskGuardPaused))
            diskGuardPaused = []
        }
    }

    // MARK: Speed limits

    private func checkAltSpeed() {
        let active = preferences.altSpeedActive()
        guard active != altSpeedActive else { return }
        altSpeedActive = active
        engine.apply(preferences, altSpeed: active)
    }

    func toggleAltSpeed() {
        preferences.altSpeedManual.toggle()
    }

    private func applyPreferences(previous: Preferences) {
        if preferences.themeID != previous.themeID {
            ThemeLibrary.shared.applyAppearance(of: Theme.current)
        }
        altSpeedActive = preferences.altSpeedActive()
        engine.apply(preferences, altSpeed: altSpeedActive)
        if preferences.effectiveBinding != previous.effectiveBinding || preferences.killSwitch != previous.killSwitch {
            publicAddress = nil  // learned again through the new route
            checkVPN()
        }
        if preferences.proxyType != previous.proxyType || preferences.proxyHost != previous.proxyHost {
            publicAddress = nil
        }
        if preferences.blocklistEnabled != previous.blocklistEnabled || preferences.blocklistURL != previous.blocklistURL {
            if preferences.blocklistEnabled { updateBlocklist() } else { engine.setBlocklist([]); blocklistRuleCount = 0 }
        }
        if preferences.defaultSavePath != previous.defaultSavePath {
            try? FileManager.default.createDirectory(atPath: preferences.defaultSavePath, withIntermediateDirectories: true)
            checkDiskSpace()
        }
    }

    // MARK: Blocklist

    private var blocklistCache: URL { stateDirectory.appendingPathComponent("blocklist.txt") }

    private func loadCachedBlocklist() {
        guard preferences.blocklistEnabled,
              let text = try? String(contentsOf: blocklistCache, encoding: .utf8) else { return }
        let ranges = Blocklist.parse(text)
        engine.setBlocklist(ranges)
        blocklistRuleCount = ranges.count
        blocklistUpdated = (try? blocklistCache.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        refreshBlocklistIfStale()
    }

    private func refreshBlocklistIfStale() {
        guard preferences.blocklistEnabled else { return }
        if let updated = blocklistUpdated, Date().timeIntervalSince(updated) < 86_400 { return }
        updateBlocklist()
    }

    func updateBlocklist() {
        let url = preferences.blocklistURL
        guard preferences.blocklistEnabled, !url.isEmpty else { return }
        Task {
            do {
                let ranges = try await Blocklist.download(from: url)
                let text = ranges.map { "\($0.0)-\($0.1)" }.joined(separator: "\n")
                try? text.write(to: blocklistCache, atomically: true, encoding: .utf8)
                engine.setBlocklist(ranges)
                blocklistRuleCount = ranges.count
                blocklistUpdated = Date()
            } catch {
                errorMessage = "Couldn't update the blocklist: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Adding

    /// Entry point for magnet links, .torrent files, drops and URLs opened by the system.
    func handleIncoming(url: URL) {
        if url.scheme?.lowercased() == "magnet" {
            requestAdd(magnet: url.absoluteString)
        } else if url.isFileURL, url.pathExtension.lowercased() == AppTheme.fileExtension {
            importTheme(from: url)
        } else if url.isFileURL {
            openTorrentFile(at: url)
        }
    }

    /// Imports a theme file and switches to it. Problems are shown in the error alert.
    func importTheme(from url: URL) {
        do {
            preferences.themeID = try ThemeLibrary.shared.importTheme(from: url).id
        } catch {
            errorMessage = "Couldn't import the theme. " + error.localizedDescription
        }
    }

    func requestAdd(magnet: String) {
        let trimmed = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("magnet:") else {
            errorMessage = "That doesn't look like a magnet link."
            return
        }
        pendingAdd = .magnet(trimmed)
    }

    func openTorrentFile(at url: URL) {
        do {
            pendingAdd = .file(try TorrentEngine.inspect(torrentFile: url.path))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseTorrentFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "torrent")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { openTorrentFile(at: url) }
    }

    func add(_ source: AddSource, savePath: String, tag: UUID?, start: Bool, sequential: Bool,
             priorities: [FilePriority]?) {
        try? FileManager.default.createDirectory(atPath: savePath, withIntermediateDirectories: true)
        let done: (Result<String, Error>) -> Void = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let hash):
                if let tag { self.tagAssignments[hash] = tag }
                self.selection = [hash]
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
        switch source {
        case .magnet(let uri):
            engine.addMagnet(uri, savePath: savePath, paused: !start, sequential: sequential, completion: done)
        case .file(let preview):
            engine.addTorrentFile(preview.path, savePath: savePath, paused: !start, sequential: sequential,
                                  priorities: priorities, completion: done)
        }
    }

    func defaultSavePath(for tag: UUID?) -> String {
        tags.first { $0.id == tag }?.savePath ?? preferences.defaultSavePath
    }

    // MARK: Actions on transfers

    /// The rows a toolbar or menu action applies to.
    func targets(_ ids: Set<String>? = nil) -> [String] { Array(ids ?? selection) }

    func pause(_ ids: Set<String>? = nil) { engine.pause(targets(ids)) }
    func resume(_ ids: Set<String>? = nil) { engine.resume(targets(ids)) }
    func pauseAll() { engine.pauseAll() }
    func resumeAll() { engine.resumeAll() }

    func requestRemove(_ ids: Set<String>? = nil) {
        let t = targets(ids)
        if !t.isEmpty { pendingRemoval = t }
    }

    func confirmRemove(deleteFiles: Bool) {
        guard let ids = pendingRemoval else { return }
        engine.remove(ids, deleteFiles: deleteFiles)
        for id in ids { tagAssignments[id] = nil; history[id] = nil }
        selection.subtract(ids)
        pendingRemoval = nil
    }

    func move(_ ids: Set<String>? = nil, _ m: TorrentEngine.QueueMove) { engine.move(targets(ids), m) }
    func recheck(_ ids: Set<String>? = nil) { engine.recheck(targets(ids)) }
    func reannounce(_ ids: Set<String>? = nil) { engine.reannounce(targets(ids)) }
    func setSequential(_ on: Bool, for id: String) { engine.setSequential(on, for: id) }
    func setPriority(_ p: FilePriority, file: Int, for id: String) {
        engine.setPriority(p, file: file, for: id)
        if var d = detail, let i = d.files.firstIndex(where: { $0.index == file }) {
            d.files[i].priority = p
            detail = d
        }
    }

    func assign(tag: UUID?, to ids: Set<String>? = nil) {
        for id in targets(ids) { tagAssignments[id] = tag }
    }

    func showInFinder(_ ids: Set<String>? = nil) {
        let urls = targets(ids).compactMap { id -> URL? in
            guard let t = transfers.first(where: { $0.id == id }) else { return nil }
            let item = URL(fileURLWithPath: t.savePath).appendingPathComponent(t.name)
            return FileManager.default.fileExists(atPath: item.path) ? item : URL(fileURLWithPath: t.savePath)
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyMagnetLinks(_ ids: Set<String>? = nil) {
        let links = targets(ids).compactMap { engine.magnetLink(for: $0) }
        guard !links.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
    }

    func chooseNewLocation(_ ids: Set<String>? = nil) {
        let t = targets(ids)
        guard !t.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        if panel.runModal() == .OK, let url = panel.url { engine.moveStorage(t, to: url.path) }
    }

    func saveBeforeQuit() {
        engine.saveState(timeout: 5, wait: true)
        sleepGuard.update(shouldHold: false)
    }

    // MARK: Tags persistence

    private struct TagFile: Codable {
        var tags: [Tag]
        var assignments: [String: UUID]
    }

    private static let defaultTags = [
        Tag(name: "Linux ISOs", color: .blue),
        Tag(name: "Open Movies", color: .orange),
        Tag(name: "Archives", color: .purple)
    ]

    private static func loadTags(from dir: URL) -> TagFile {
        let url = dir.appendingPathComponent("tags.json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TagFile.self, from: data) else {
            return TagFile(tags: [], assignments: [:])
        }
        return file
    }

    private func saveTags() {
        let file = TagFile(tags: tags, assignments: tagAssignments)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: stateDirectory.appendingPathComponent("tags.json"), options: .atomic)
        }
    }
}
