import AppKit
import ApplicationServices
import Foundation
import PlaylistCore

public struct MusicAccessibilityDriver: MusicAppClient, Sendable {
    private let accessibility: any AccessibilityProviding
    private let urlOpener: any URLOpening
    private let scripts: MusicScriptReader
    private let pollInterval: Duration
    private let directLookupTimeout: Duration

    public init(
        accessibility: any AccessibilityProviding = AXMusicAccessibilityProvider(),
        urlOpener: any URLOpening = MusicURLOpener(),
        scripts: MusicScriptReader = MusicScriptReader(),
        pollInterval: Duration = .milliseconds(150),
        directLookupTimeout: Duration = .seconds(3)
    ) {
        self.accessibility = accessibility
        self.urlOpener = urlOpener
        self.scripts = scripts
        self.pollInterval = pollInterval
        self.directLookupTimeout = directLookupTimeout
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
        let directDeadline = min(deadline, clock.now.advanced(by: directLookupTimeout))

        if let more = try await poll(until: directDeadline, matching: { tree in
            AccessibilityMatcher.trackMoreButton(catalogID: track.id, in: tree)
        }) {
            return try await submit(more: more, track: track, to: playlist, until: deadline)
        }

        guard clock.now < deadline else { return .notFound }
        let navigationTree = try accessibility.musicTree()
        if let searchRow = AccessibilityMatcher.sidebarSearchRow(in: navigationTree) {
            try accessibility.press(path: searchRow)
        } else {
            try accessibility.send(.commandF)
        }
        guard let searchField = try await poll(until: deadline, matching: { tree in
            AccessibilityMatcher.readySearchField(in: tree)
        }) else { return .notFound }

        try accessibility.setValue("\(track.name) \(track.artist)", path: searchField)
        if pollInterval > .zero {
            try await Task.sleep(for: pollInterval)
        }
        try accessibility.send(.returnKey)

        guard let result = try await poll(until: deadline, matching: { tree in
            AccessibilityMatcher.topSearchResult(catalogID: track.id, in: tree)
                ?? track.albumID.flatMap { AccessibilityMatcher.albumSearchResult(albumID: $0, in: tree) }
        }) else { return .notFound }
        try accessibility.press(path: result)

        guard let more = try await poll(until: deadline, matching: { tree in
            AccessibilityMatcher.trackMoreButton(catalogID: track.id, in: tree)
        }) else { return .notFound }
        return try await submit(more: more, track: track, to: playlist, until: deadline)
    }

    private func poll(
        until deadline: ContinuousClock.Instant,
        matching: @Sendable (AccessibilityNodeSnapshot) -> AccessibilityPath?
    ) async throws -> AccessibilityPath? {
        let clock = ContinuousClock()
        while true {
            let tree = try accessibility.musicTree()
            if let match = matching(tree) { return match }
            guard clock.now < deadline else { return nil }
            if pollInterval > .zero {
                try await Task.sleep(for: pollInterval)
            }
        }
    }

    private func submit(
        more: AccessibilityPath,
        track: CatalogTrack,
        to playlist: String,
        until deadline: ContinuousClock.Instant
    ) async throws -> AddTrackOutcome {
        try pressAllowingCannotComplete(path: more)
        let menuTree = try accessibility.musicTree()
        if let target = AccessibilityMatcher.playlistMenuItem(named: playlist, in: menuTree) {
            try pressAllowingCannotComplete(path: target)
            return .submitted
        }
        guard let menu = AccessibilityMatcher.menu(in: menuTree) else { return .notFound }
        do {
            try accessibility.cancel(path: menu)
        } catch AccessibilityDriverError.invalidPath {
            try accessibility.send(.escape)
        }
        let postCancelTree = try accessibility.musicTree()
        if AccessibilityMatcher.menu(in: postCancelTree) != nil {
            try accessibility.send(.escape)
        }
        try await urlOpener.openInMusic(track.url)
        let clock = ContinuousClock()
        while true {
            let tree = try accessibility.musicTree()
            let source = AccessibilityMatcher.trackContainer(catalogID: track.id, in: tree)
            let destination = AccessibilityMatcher.sidebarPlaylistRow(named: playlist, in: tree)
            if let openMenu = AccessibilityMatcher.menu(in: tree) {
                do {
                    try accessibility.cancel(path: openMenu)
                } catch {
                    try accessibility.send(.escape)
                }
                guard clock.now < deadline else { return .notFound }
                if pollInterval > .zero { try await Task.sleep(for: pollInterval) }
                continue
            }
            if source != nil, destination != nil {
                try await scripts.duplicateUniqueLibraryTrack(track, to: playlist)
                return .submitted
            }
            guard clock.now < deadline else { return .notFound }
            if pollInterval > .zero { try await Task.sleep(for: pollInterval) }
        }
    }

    private func pressAllowingCannotComplete(path: AccessibilityPath) throws {
        do {
            try accessibility.press(path: path)
        } catch AccessibilityDriverError.pressFailed(-25204, _) {
            // Music 有时已经完成 AXPress 并打开菜单，却仍返回 kAXErrorCannotComplete。
            // 调用方随后必须通过菜单或写后回读验证后置条件。
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
    case pressFailed(Int32, String)
    case focusFailed(Int32)
    case valueSetFailed(Int32)
    case keyEventCreationFailed

    public var errorDescription: String? {
        switch self {
        case .musicNotRunning: "“音乐”App 尚未运行。"
        case let .attributeReadFailed(attribute): "无法读取“音乐”的辅助功能属性：\(attribute)。"
        case .invalidPath: "辅助功能元素路径已失效，未执行点击。"
        case let .pressFailed(code, element): "辅助功能按压失败（错误码 \(code)，元素：\(element)）。"
        case let .focusFailed(code): "无法聚焦 Music 搜索框（错误码 \(code)）。"
        case let .valueSetFailed(code): "无法写入 Music 搜索框（错误码 \(code)）。"
        case .keyEventCreationFailed: "无法创建 Music 键盘事件。"
        }
    }
}

public final class AXMusicAccessibilityProvider: AccessibilityProviding, @unchecked Sendable {
    private let cacheLock = NSLock()
    private var elementCache: [AccessibilityPath: AXUIElement] = [:]

    public init() {}
    public func isAuthorized() -> Bool { AXIsProcessTrusted() }

    public func musicTree() throws -> AccessibilityNodeSnapshot {
        var cache: [AccessibilityPath: AXUIElement] = [:]
        let tree = snapshot(element: try applicationElement(), depth: 0, path: [], cache: &cache)
        cacheLock.lock()
        elementCache = cache
        cacheLock.unlock()
        return tree
    }

    public func press(path: AccessibilityPath) throws {
        let element = try element(at: path)
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard error == .success else {
            throw AccessibilityDriverError.pressFailed(error.rawValue, diagnosticDescription(of: element))
        }
    }

    public func setValue(_ value: String, path: AccessibilityPath) throws {
        let element = try element(at: path)
        let focusError = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        guard focusError == .success else { throw AccessibilityDriverError.focusFailed(focusError.rawValue) }
        let error = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            value as CFString
        )
        guard error == .success else { throw AccessibilityDriverError.valueSetFailed(error.rawValue) }
    }

    public func send(_ keyStroke: MusicKeyStroke) throws {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            throw AccessibilityDriverError.musicNotRunning
        }
        app.activate()
        let activationDeadline = Date().addingTimeInterval(1)
        while !app.isActive && Date() < activationDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        let virtualKey: CGKeyCode
        let flags: CGEventFlags
        switch keyStroke {
        case .commandF:
            virtualKey = 3
            flags = .maskCommand
        case .returnKey:
            virtualKey = 36
            flags = []
        case .escape:
            virtualKey = 53
            flags = []
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            throw AccessibilityDriverError.keyEventCreationFailed
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(app.processIdentifier)
        keyUp.postToPid(app.processIdentifier)
    }

    private func element(at path: AccessibilityPath) throws -> AXUIElement {
        cacheLock.lock()
        let cached = elementCache[path]
        cacheLock.unlock()
        if let cached { return cached }
        var element = try applicationElement()
        for index in path.indices {
            let currentChildren = children(of: element)
            guard currentChildren.indices.contains(index) else { throw AccessibilityDriverError.invalidPath }
            element = currentChildren[index]
        }
        return element
    }

    private func diagnosticDescription(of element: AXUIElement) -> String {
        let role = stringAttribute(kAXRoleAttribute, of: element) ?? "unknown-role"
        let identifier = stringAttribute(kAXIdentifierAttribute, of: element) ?? "no-id"
        let title = stringAttribute(kAXTitleAttribute, of: element)
            ?? stringAttribute(kAXDescriptionAttribute, of: element)
            ?? "no-title"
        var actionValue: CFArray?
        let actionError = AXUIElementCopyActionNames(element, &actionValue)
        let actions = actionError == .success ? (actionValue as? [String] ?? []) : []
        return "\(role), \(identifier), \(title), actions=\(actions.joined(separator: ","))"
    }

    private func applicationElement() throws -> AXUIElement {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            throw AccessibilityDriverError.musicNotRunning
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private func snapshot(
        element: AXUIElement,
        depth: Int,
        path: [Int],
        cache: inout [AccessibilityPath: AXUIElement]
    ) -> AccessibilityNodeSnapshot {
        guard depth < 40 else { return AccessibilityNodeSnapshot() }
        cache[AccessibilityPath(indices: path)] = element
        let childElements = children(of: element)
        return AccessibilityNodeSnapshot(
            identifier: stringAttribute(kAXIdentifierAttribute, of: element),
            role: stringAttribute(kAXRoleAttribute, of: element),
            title: stringAttribute(kAXTitleAttribute, of: element),
            description: stringAttribute(kAXDescriptionAttribute, of: element),
            value: stringAttribute(kAXValueAttribute, of: element),
            children: childElements.enumerated().map { index, child in
                snapshot(element: child, depth: depth + 1, path: path + [index], cache: &cache)
            }
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


    public func cancel(path: AccessibilityPath) throws {
        let element = try element(at: path)
        let error = AXUIElementPerformAction(element, kAXCancelAction as CFString)
        guard error == .success || error.rawValue == -25204 else {
            throw AccessibilityDriverError.pressFailed(error.rawValue, diagnosticDescription(of: element))
        }
    }

}
