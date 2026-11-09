import Foundation
import TorrentBridge

/// Swift face of the libtorrent session. All calls run on one background queue so
/// the main thread never waits on libtorrent's network thread.
final class TorrentEngine: @unchecked Sendable {
    struct Snapshot {
        var transfers: [Transfer]
        var session: SessionInfo
        var events: [SWEvent]
    }

    private let session: SWSession
    let queue = DispatchQueue(label: "app.peerbloom.engine", qos: .userInitiated)
    /// The interface the session was last bound to (nil for none). Changed only on the main thread.
    private(set) var appliedInterface: String?

    init(preferences: Preferences, stateDirectory: URL) {
        let s = Self.settings(from: preferences, altSpeed: false)
        appliedInterface = s.boundInterface
        session = SWSession(settings: s, stateDirectory: stateDirectory.path)
    }

    /// The interface to bind to. "Any active VPN" follows whichever tunnel is up; with none up it binds to
    /// loopback, so nothing leaves the Mac until a VPN connects.
    static func boundInterface(for p: Preferences, interfaces: [NetworkInterface]) -> String? {
        guard p.effectiveBinding == Preferences.anyVPN else { return p.effectiveBinding }
        return NetworkInterfaces.activeVPN(in: interfaces)?.name ?? "lo0"
    }

    static func settings(from p: Preferences, altSpeed: Bool) -> SWSessionSettings {
        let s = SWSessionSettings()
        s.listenPort = Int32(p.listenPort)
        s.boundInterface = boundInterface(for: p, interfaces: NetworkInterfaces.current())
        let down = altSpeed ? p.altDownloadLimitKB : p.downloadLimitKB
        let up = altSpeed ? p.altUploadLimitKB : p.uploadLimitKB
        s.downloadRateLimit = Int32(clamping: down * 1024)
        s.uploadRateLimit = Int32(clamping: up * 1024)
        switch p.effectiveEncryption {
        case .require: s.encryption = .require
        case .prefer: s.encryption = .prefer
        case .allow: s.encryption = .allow
        }
        s.anonymousMode = p.effectiveAnonymousMode
        s.enableDHT = p.enableDHT
        s.enableLSD = p.effectiveLSD
        s.enablePortMapping = p.effectivePortMapping
        switch p.proxyType {
        case .none: s.proxyType = .none
        case .socks5: s.proxyType = .SOCKS5
        case .http: s.proxyType = .HTTP
        }
        s.proxyHost = p.proxyHost.trimmingCharacters(in: .whitespaces)
        s.proxyPort = Int32(clamping: p.proxyPort)
        s.proxyUsername = p.proxyUsername
        s.proxyPassword = p.proxyType == .none || p.proxyUsername.isEmpty ? "" : Keychain.proxyPassword
        s.proxyPeerConnections = p.proxyPeerConnections
        s.proxyTrackerConnections = p.proxyTrackerConnections
        s.activeDownloads = Int32(p.activeDownloads)
        s.activeSeeds = Int32(p.activeSeeds)
        s.clientVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return s
    }

    func apply(_ preferences: Preferences, altSpeed: Bool) {
        let s = Self.settings(from: preferences, altSpeed: altSpeed)
        appliedInterface = s.boundInterface
        queue.async { self.session.apply(s) }
    }

    // MARK: Polling

    func snapshot(completion: @escaping (Snapshot) -> Void) {
        queue.async {
            let transfers = self.session.allStatuses().map(Self.transfer(from:))
            let stats = self.session.sessionStats()
            let events = self.session.popEvents()
            let info = SessionInfo(dhtNodes: Int(stats.dhtNodes), listenPort: Int(stats.listenPort),
                                   listening: stats.listening, portMapped: stats.portMapped,
                                   totalDownload: stats.totalDownload, totalUpload: stats.totalUpload)
            let snap = Snapshot(transfers: transfers, session: info, events: events)
            DispatchQueue.main.async { completion(snap) }
        }
    }

    func detail(for hash: String, buckets: Int, completion: @escaping (TransferDetail?) -> Void) {
        queue.async {
            let d = self.session.detail(forHash: hash, bucketCount: Int32(buckets)).map(Self.detail(from:))
            DispatchQueue.main.async { completion(d) }
        }
    }

    private static func transfer(from s: SWTorrentStatus) -> Transfer {
        let state: TransferState
        if s.errorMessage != nil {
            state = .error
        } else if s.paused && !s.autoManaged {
            state = .paused
        } else if s.paused {
            state = .queued
        } else {
            switch s.state {
            case .checkingFiles, .checkingResumeData: state = .checking
            case .downloadingMetadata: state = .fetchingMetadata
            case .downloading: state = .downloading
            case .seeding: state = .seeding
            case .finished: state = .completed
            default: state = .downloading
            }
        }
        return Transfer(
            id: s.infoHash, name: s.name, savePath: s.savePath, state: state,
            isPaused: s.paused && !s.autoManaged, sequential: s.sequential, hasMetadata: s.hasMetadata,
            progress: s.progress, totalWanted: s.totalWanted, totalDone: s.totalWantedDone,
            uploaded: s.allTimeUpload, downloaded: s.allTimeDownload,
            downloadRate: Int(s.downloadRate), uploadRate: Int(s.uploadRate),
            peers: Int(s.numPeers), seeds: Int(s.numSeeds),
            knownPeers: Int(s.listPeers), knownSeeds: Int(s.listSeeds),
            availability: s.availability, queuePosition: Int(s.queuePosition),
            addedDate: s.addedDate, completedDate: s.completedDate, errorMessage: s.errorMessage)
    }

    private static func detail(from d: SWTorrentDetail) -> TransferDetail {
        TransferDetail(
            files: d.files.map {
                FileItem(index: Int($0.index), path: $0.path, size: $0.size,
                         downloaded: $0.downloaded, priority: FilePriority(libtorrent: Int($0.priority)))
            },
            peers: d.peers.map {
                PeerItem(address: $0.address, client: $0.client.isEmpty ? "Unknown" : $0.client,
                         downloadRate: Int($0.downloadRate), uploadRate: Int($0.uploadRate),
                         progress: $0.progress, encrypted: $0.encrypted, isSeed: $0.seed)
            },
            trackers: d.trackers.map {
                TrackerItem(url: $0.url, tier: Int($0.tier), working: $0.working, updating: $0.updating,
                            seeds: Int($0.seeds), peers: Int($0.peers), message: $0.message)
            },
            pieceBuckets: d.pieceBuckets.map(\.doubleValue),
            pieceCount: Int(d.pieceCount), pieceSize: Int(d.pieceSize), comment: d.comment)
    }

    // MARK: Adding

    static func inspect(torrentFile path: String) throws -> TorrentPreview {
        let info = try SWSession.inspectTorrentFile(path)
        return TorrentPreview(
            path: path, name: info.name, infoHash: info.infoHash, totalSize: info.totalSize,
            files: info.files.map {
                FileItem(index: Int($0.index), path: $0.path, size: $0.size, downloaded: 0, priority: .normal)
            })
    }

    func addMagnet(_ uri: String, savePath: String, paused: Bool, sequential: Bool,
                   completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            let result = Result { try self.session.addMagnet(uri, savePath: savePath, paused: paused, sequential: sequential) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func addTorrentFile(_ path: String, savePath: String, paused: Bool, sequential: Bool,
                        priorities: [FilePriority]?, completion: @escaping (Result<String, Error>) -> Void) {
        let prios = priorities?.map { NSNumber(value: $0.rawValue) }
        queue.async {
            let result = Result {
                try self.session.addTorrentFile(path, savePath: savePath, paused: paused,
                                                sequential: sequential, filePriorities: prios)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: Actions

    func pause(_ hashes: [String]) { queue.async { hashes.forEach(self.session.pause) } }
    func resume(_ hashes: [String]) { queue.async { hashes.forEach(self.session.resume) } }
    func pauseAll() { queue.async { self.session.pauseAll() } }
    func resumeAll() { queue.async { self.session.resumeAll() } }

    func remove(_ hashes: [String], deleteFiles: Bool) {
        queue.async { hashes.forEach { self.session.remove($0, deleteFiles: deleteFiles) } }
    }

    func setSequential(_ on: Bool, for hash: String) { queue.async { self.session.setSequential(on, forHash: hash) } }

    func setPriority(_ p: FilePriority, file index: Int, for hash: String) {
        queue.async { self.session.setFilePriority(Int32(p.rawValue), fileIndex: Int32(index), forHash: hash) }
    }

    enum QueueMove { case top, up, down, bottom }

    func move(_ hashes: [String], _ move: QueueMove) {
        queue.async {
            for h in hashes {
                switch move {
                case .top: self.session.queueTop(h)
                case .up: self.session.queueUp(h)
                case .down: self.session.queueDown(h)
                case .bottom: self.session.queueBottom(h)
                }
            }
        }
    }

    func moveStorage(_ hashes: [String], to path: String) { queue.async { hashes.forEach { self.session.moveStorage($0, to: path) } } }
    func recheck(_ hashes: [String]) { queue.async { hashes.forEach(self.session.forceRecheck) } }
    func reannounce(_ hashes: [String]) { queue.async { hashes.forEach(self.session.forceReannounce) } }

    func magnetLink(for hash: String) -> String? {
        queue.sync { session.magnetLink(forHash: hash) }
    }

    func setBlocklist(_ ranges: [(String, String)]) {
        let objs = ranges.map { SWIPRange(first: $0.0, last: $0.1) }
        queue.async { self.session.setBlockedRanges(objs) }
    }

    /// Saves resume data so progress survives a restart. Blocks the engine queue for up to `timeout`.
    func saveState(timeout: TimeInterval, wait: Bool) {
        if wait {
            queue.sync { session.saveState(withTimeout: timeout) }
        } else {
            queue.async { self.session.saveState(withTimeout: timeout) }
        }
    }
}
