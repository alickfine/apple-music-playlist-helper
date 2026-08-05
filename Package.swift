// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppleMusicPlaylistHelper",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PlaylistCore", targets: ["PlaylistCore"]),
        .library(name: "MusicAccessibilityDriver", targets: ["MusicAccessibilityDriver"]),
    ],
    targets: [
        .target(name: "PlaylistCore"),
        .target(name: "MusicAccessibilityDriver", dependencies: ["PlaylistCore"]),
        .testTarget(name: "PlaylistCoreTests", dependencies: ["PlaylistCore"]),
        .testTarget(name: "MusicAccessibilityDriverTests", dependencies: ["MusicAccessibilityDriver", "PlaylistCore"]),
    ]
)
