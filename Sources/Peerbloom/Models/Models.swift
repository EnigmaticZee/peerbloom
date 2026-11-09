import Foundation

enum TransferState: String, Codable {
    case checking, fetchingMetadata, downloading, seeding, completed, paused, queued, error

    var label: String {
        switch self {
        case .checking: "Checking"
        case .fetchingMetadata: "Fetching info"
        case .downloading: "Downloading"
        case .seeding: "Seeding"
        case .completed: "Completed"
        case .paused: "Paused"
        case .queued: "Queued"
        case .error: "Error"
        }
    }

    /// Used to sort the Status column in a sensible order.
    var sortRank: Int {
        switch self {
        case .downloading: 0
        case .fetchingMetadata: 1
        case .checking: 2
        case .seeding: 3
        case .queued: 4
        case .paused: 5
        case .completed: 6
        case .error: 7
        }
    }
}

/// Sidebar status filters.
enum StatusFilter: String, CaseIterable, Identifiable, Hashable {
    case all, downloading, seeding, completed, pausedQueued

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Transfers"
        case .downloading: "Downloading"
        case .seeding: "Seeding"
        case .completed: "Completed"
        case .pausedQueued: "Paused & Queued"
        }
    }

    var symbol: String {
        switch self {
        case .all: "line.3.horizontal"
        case .downloading: "arrow.down.to.line"
        case .seeding: "arrow.up.to.line"
        case .completed: "checkmark"
        case .pausedQueued: "pause"
        }
    }

    func matches(_ t: Transfer) -> Bool {
        switch self {
        case .all: true
        case .downloading: [.downloading, .fetchingMetadata, .checking].contains(t.state)
        case .seeding: t.state == .seeding
        case .completed: t.state == .completed
        case .pausedQueued: [.paused, .queued, .error].contains(t.state)
        }
    }
}

enum SidebarSelection: Hashable {
    case status(StatusFilter)
    case tag(UUID)
}

struct Transfer: Identifiable, Hashable {
    let id: String              // info hash, hex
    var name: String
    var savePath: String
    var state: TransferState
    var isPaused: Bool
    var sequential: Bool
    var hasMetadata: Bool
    var progress: Double        // 0...1
    var totalWanted: Int64
    var totalDone: Int64
    var uploaded: Int64
    var downloaded: Int64
    var downloadRate: Int
    var uploadRate: Int
    var peers: Int
    var seeds: Int
    var knownPeers: Int
    var knownSeeds: Int
    var availability: Double
    var queuePosition: Int
    var addedDate: Date
    var completedDate: Date?
    var errorMessage: String?

    var ratio: Double {
        let base = max(downloaded, totalDone)
        return base > 0 ? Double(uploaded) / Double(base) : 0
    }

    /// Seconds left, or nil when it can't be estimated.
    var eta: TimeInterval? {
        guard state == .downloading, downloadRate > 0 else { return nil }
        return Double(totalWanted - totalDone) / Double(downloadRate)
    }

    // Sort keys for the table (KeyPathComparator needs Comparable values).
    var sortSize: Int64 { totalWanted }
    var sortStatus: Int { state.sortRank }
    var sortETA: Double { eta ?? .greatestFiniteMagnitude }
    var sortQueue: Int { queuePosition < 0 ? Int.max : queuePosition }

    var isActive: Bool { state == .downloading || state == .seeding || state == .fetchingMetadata }
}

struct FileItem: Identifiable, Hashable {
    var id: Int { index }
    let index: Int
    let path: String
    let size: Int64
    var downloaded: Int64
    var priority: FilePriority

    var name: String { (path as NSString).lastPathComponent }
    var progress: Double { size > 0 ? Double(downloaded) / Double(size) : 1 }
}

enum FilePriority: Int, CaseIterable, Identifiable {
    case skip = 0, low = 1, normal = 4, high = 7
    var id: Int { rawValue }

    init(libtorrent value: Int) {
        switch value {
        case 0: self = .skip
        case 1...3: self = .low
        case 4...5: self = .normal
        default: self = .high
        }
    }

    var label: String {
        switch self {
        case .skip: "Skip"
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }
}

struct PeerItem: Identifiable, Hashable {
    var id: String { address }
    let address: String
    let client: String
    let downloadRate: Int
    let uploadRate: Int
    let progress: Double
    let encrypted: Bool
    let isSeed: Bool
}

struct TrackerItem: Identifiable, Hashable {
    var id: String { url }
    let url: String
    let tier: Int
    let working: Bool
    let updating: Bool
    let seeds: Int
    let peers: Int
    let message: String
}

struct TransferDetail {
    var files: [FileItem] = []
    var peers: [PeerItem] = []
    var trackers: [TrackerItem] = []
    var pieceBuckets: [Double] = []
    var pieceCount = 0
    var pieceSize = 0
    var comment: String?
}

struct SpeedSample: Identifiable {
    let id: Int
    let time: Date
    let down: Int
    let up: Int
}

/// Contents of a .torrent file, shown in the Add sheet before adding it.
struct TorrentPreview {
    let path: String
    let name: String
    let infoHash: String
    let totalSize: Int64
    let files: [FileItem]
}

struct Tag: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var color: TagColor
    /// When set, transfers given this tag are saved here by default.
    var savePath: String?
}

enum TagColor: String, Codable, CaseIterable, Identifiable {
    case blue, orange, purple, green, pink, gray
    var id: String { rawValue }
}

enum VPNStatus: Equatable {
    case notBound
    case protected(String)  // bound to a VPN tunnel that is up
    case bound(String)      // bound to a regular connection (Wi-Fi, Ethernet): locked to it, but not a VPN
    case down(String)       // bound interface is gone; the kill switch has paused traffic
    case waitingForVPN      // set to follow any active VPN, and none is connected; nothing leaves the Mac
}

/// A transfer found to contain apps, installers or scripts after its file list arrived.
struct RiskyAlert: Identifiable, Equatable {
    let id: String   // info hash
    let name: String
    let findings: [RiskyFiles.Finding]
}

struct SessionInfo {
    var dhtNodes = 0
    var listenPort = 0
    var listening = false
    var portMapped = false
    var totalDownload: Int64 = 0
    var totalUpload: Int64 = 0
}
