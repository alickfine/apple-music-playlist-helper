import AppKit
import ApplicationServices
import Foundation
import PlaylistCore

public struct MusicAccessibilityDriver: MusicAppClient, Sendable {
    private let accessibility: any AccessibilityProviding
    private let urlOpener: any URLOpening
    private let scripts: MusicScriptReader
    private let pollInterval: Duration

    public init(
        accessibility: any AccessibilityProviding = AXMusicAccessibilityProvider(),
        urlOpener: any URLOpening = MusicURLOpener(),
        scripts: MusicScriptReader = MusicScriptReader(),
        pollInterval: Duration = .milliseconds(150)
    ) {
        self.accessibility = accessibility
        self.urlOpener = urlOpener
        self.scripts = scripts
        self.pollInterval = pollInterval
    }

    public func accessibilityAuthorized() async -> Bool {
        accessibility.isAuthorized()
    }

    public func playlist(named: String) async throws -> PlaylistSnapshot? {
        try await scripts.playlist(named: named)
    }

    public func createPlaylist(named: String) async throws {
        try await scripts.createPlaylist(named: named)
    }

    public func add(
        _ track: CatalogTrack,
        to playlist: String,
        timeout: Duration
    ) async throws -> AddTrackOutcome {
        try await urlOpener.openInMusic(track.url)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while true {
            let tree = try accessibility.musicTree()
            if let more = AccessibilityMatcher.trackMoreButton(catalogID: track.id, in: tree) {
                try accessibility.press(path: more)
                let menuTree = try accessibility.musicTree()
                guard let target = AccessibilityMatcher.playlistMenuItem(named: playlist, in: menuTree) else {
                    return .notFound
                }
                try accessibility.press(path: target)
                return .submitted
            }
            guard clock.now < deadline else { return .notFound }
            if pollInterval > .zero {
                try await Task.sleep(for: pollInterval)
            }
        }
    }

    public func remove(_ track: RemovalTrack, from playlist: String) async throws {
        try await scripts.remove(track, from: playlist)
    }

    public func play(track: CatalogTrack, in playlist: String) async throws {
        try await scripts.play(track: track, in: playlist)
    }
}

public struct MusicURLOpener: URLOpening, Sendable {
    private let runner: any ProcessRunning
    public init(runner: any ProcessRunning = ProcessRunner()) { self.runner = runner }

    public func openInMusic(_ url: URL) async throws {
        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", "Music", url.absoluteString],
            stdin: nil
        )
        guard result.exitCode == 0 else {
            throw MusicScriptError.executionFailed(
                exitCode: result.exitCode,
                diagnostic: String(decoding: result.stderr, as: UTF8.self)
            )
        }
    }
}

public enum AccessibilityDriverError: LocalizedError, Sendable {
    case musicNotRunning
    case attributeReadFailed(String)
    case invalidPath
    case pressFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .musicNotRunning: "“音乐”App 尚未运行。"
        case let .attributeReadFailed(attribute): "无法读取“音乐”的辅助功能属性：\(attribute)。"
        case .invalidPath: "辅助功能元素路径已失效，未执行点击。"
        case let .pressFailed(code): "辅助功能按压失败（错误码 \(code)）。"
        }
    }
}

public final class AXMusicAccessibilityProvider: AccessibilityProviding, @unchecked Sendable {
    public init() {}
    public func isAuthorized() -> Bool { AXIsProcessTrusted() }

    public func musicTree() throws -> AccessibilityNodeSnapshot {
        snapshot(element: try applicationElement(), depth: 0)
    }

    public func press(path: AccessibilityPath) throws {
        var element = try applicationElement()
        for index in path.indices {
            let children = children(of: element)
            guard children.indices.contains(index) else { throw AccessibilityDriverError.invalidPath }
            element = children[index]
        }
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard error == .success else { throw AccessibilityDriverError.pressFailed(error.rawValue) }
    }

    private func applicationElement() throws -> AXUIElement {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            throw AccessibilityDriverError.musicNotRunning
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func snapshot(element: AXUIElement, depth: Int) -> AccessibilityNodeSnapshot {
        guard depth < 40 else { return AccessibilityNodeSnapshot() }
        return AccessibilityNodeSnapshot(
            identifier: stringAttribute(kAXIdentifierAttribute, of: element),
            role: stringAttribute(kAXRoleAttribute, of: element),
            title: stringAttribute(kAXTitleAttribute, of: element),
            description: stringAttribute(kAXDescriptionAttribute, of: element),
            children: children(of: element).map { snapshot(element: $0, depth: depth + 1) }
        )
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
