// swift-tools-version: 6.0
import PackageDescription

let homebrew = "/opt/homebrew"

let package = Package(
    name: "Peerbloom",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Peerbloom", targets: ["Peerbloom"])
    ],
    targets: [
        // Objective-C++ wrapper that hides libtorrent's C++ API behind a small Objective-C one Swift can call.
        // libtorrent comes from Homebrew: brew install libtorrent-rasterbar
        // The defines must match how Homebrew built the library (see: pkg-config --cflags libtorrent-rasterbar).
        .target(
            name: "TorrentBridge",
            path: "Sources/TorrentBridge",
            cxxSettings: [
                .define("TORRENT_LINKING_SHARED"),
                .define("BOOST_ASIO_NO_DEPRECATED"),
                .define("BOOST_SYSTEM_USE_UTF8"),
                .define("TORRENT_ABI_VERSION", to: "2"),
                .define("TORRENT_USE_OPENSSL"),
                .define("TORRENT_USE_LIBCRYPTO"),
                .define("TORRENT_SSL_PEERS"),
                .unsafeFlags(["-fobjc-arc", "-fexceptions", "-I\(homebrew)/include"])
            ],
            linkerSettings: [
                .linkedLibrary("torrent-rasterbar"),
                .unsafeFlags(["-L\(homebrew)/lib"])
            ]
        ),
        .executableTarget(
            name: "Peerbloom",
            dependencies: ["TorrentBridge"],
            path: "Sources/Peerbloom"
        ),
        .testTarget(
            name: "PeerbloomTests",
            dependencies: ["Peerbloom"],
            path: "Tests/PeerbloomTests"
        )
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
