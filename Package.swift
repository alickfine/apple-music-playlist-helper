// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppleMusicPlaylistHelper",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PlaylistCore", targets: ["PlaylistCore"]),
    ],
    targets: [
        .target(name: "PlaylistCore"),
        .testTarget(name: "PlaylistCoreTests", dependencies: ["PlaylistCore"]),
    ]
)
