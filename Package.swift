// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppleMusicPlaylistHelper",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PlaylistCore", targets: ["PlaylistCore"]),
        .library(name: "MusicAccessibilityDriver", targets: ["MusicAccessibilityDriver"]),
        .library(name: "AMPlaylistCLIKit", targets: ["AMPlaylistCLIKit"]),
        .executable(name: "am-playlist", targets: ["am-playlist"]),
    ],
    targets: [
        .target(name: "PlaylistCore"),
        .target(name: "MusicAccessibilityDriver", dependencies: ["PlaylistCore"]),
        .target(name: "AMPlaylistCLIKit", dependencies: ["PlaylistCore"]),
        .executableTarget(name: "am-playlist", dependencies: ["PlaylistCore", "MusicAccessibilityDriver", "AMPlaylistCLIKit"]),
        .testTarget(name: "PlaylistCoreTests", dependencies: ["PlaylistCore"]),
        .testTarget(name: "MusicAccessibilityDriverTests", dependencies: ["MusicAccessibilityDriver", "PlaylistCore"]),
        .testTarget(name: "AMPlaylistCLIKitTests", dependencies: ["AMPlaylistCLIKit", "PlaylistCore"]),
    ]
)
