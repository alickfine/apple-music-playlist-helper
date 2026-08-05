import Foundation
import XCTest
@testable import MusicAccessibilityDriver
import PlaylistCore

final class MusicAccessibilityDriverTests: XCTestCase {
    private let track = CatalogTrack(
        id: "905228611", name: "被遗忘的时光", artist: "蔡琴",
        url: URL(string: "https://music.apple.com/cn/album/example/905228600?i=905228611")!
    )

    func testOpensExactURLAndPressesMoreThenExactPlaylist() async throws {
        let provider = FakeAccessibilityProvider(trees: [trackTree, menuTree])
        let opener = FakeURLOpener()
        let driver = MusicAccessibilityDriver(
            accessibility: provider, urlOpener: opener, scripts: MusicScriptReader(runner: NoopRunner()), pollInterval: .zero
        )
        let result = try await driver.add(track, to: "试音", timeout: .seconds(1))
        XCTAssertEqual(result, .submitted)
        XCTAssertEqual(opener.openedURLs, [track.url])
        XCTAssertEqual(provider.pressedPaths, [.init(indices: [0, 0]), .init(indices: [0, 0])])
    }

    func testPollsUntilExactCatalogIDAppears() async throws {
        let provider = FakeAccessibilityProvider(trees: [emptyTree, trackTree, menuTree])
        let driver = MusicAccessibilityDriver(
            accessibility: provider, urlOpener: FakeURLOpener(), scripts: MusicScriptReader(runner: NoopRunner()), pollInterval: .zero
        )
        let result = try await driver.add(track, to: "试音", timeout: .seconds(1))
        XCTAssertEqual(result, .submitted)
        XCTAssertEqual(provider.treeReadCount, 3)
    }

    func testZeroTimeoutReturnsNotFoundWithoutPressing() async throws {
        let provider = FakeAccessibilityProvider(trees: [emptyTree])
        let driver = MusicAccessibilityDriver(
            accessibility: provider, urlOpener: FakeURLOpener(), scripts: MusicScriptReader(runner: NoopRunner()), pollInterval: .zero
        )
        let result = try await driver.add(track, to: "试音", timeout: .zero)
        XCTAssertEqual(result, .notFound)
        XCTAssertTrue(provider.pressedPaths.isEmpty)
    }

    func testMissingPlaylistMenuDoesNotPerformSecondPress() async throws {
        let provider = FakeAccessibilityProvider(trees: [trackTree, emptyTree])
        let driver = MusicAccessibilityDriver(
            accessibility: provider, urlOpener: FakeURLOpener(), scripts: MusicScriptReader(runner: NoopRunner()), pollInterval: .zero
        )
        let result = try await driver.add(track, to: "试音", timeout: .seconds(1))
        XCTAssertEqual(result, .notFound)
        XCTAssertEqual(provider.pressedPaths.count, 1)
    }

    func testProviderRecordsExactSearchInteraction() throws {
        let provider = FakeAccessibilityProvider(trees: [emptyTree])
        let searchPath = AccessibilityPath(indices: [0, 1])

        try provider.setValue("被遗忘的时光 蔡琴", path: searchPath)
        try provider.send(.commandF)
        try provider.send(.downArrow)
        try provider.send(.returnKey)

        XCTAssertEqual(
            provider.setValues,
            [.init(value: "被遗忘的时光 蔡琴", path: searchPath)]
        )
        XCTAssertEqual(provider.sentKeys, [.commandF, .downArrow, .returnKey])
    }

    func testFallsBackToExactSearchResultAndRevalidatesAlbumTrack() async throws {
        let provider = FakeAccessibilityProvider(trees: [
            emptyTree,
            searchFieldTree,
            topSearchTrackTree,
            trackTree,
            menuTree
        ])
        let opener = FakeURLOpener()
        let driver = MusicAccessibilityDriver(
            accessibility: provider,
            urlOpener: opener,
            scripts: MusicScriptReader(runner: NoopRunner()),
            pollInterval: .zero,
            directLookupTimeout: .zero
        )

        let result = try await driver.add(track, to: "试音", timeout: .seconds(1))

        XCTAssertEqual(result, .submitted)
        XCTAssertEqual(opener.openedURLs, [track.url])
        XCTAssertEqual(provider.sentKeys, [.commandF, .downArrow, .returnKey])
        XCTAssertEqual(provider.setValues, [.init(value: "被遗忘的时光 蔡琴", path: .init(indices: [0]))])
        XCTAssertEqual(
            provider.pressedPaths,
            [.init(indices: [0]), .init(indices: [0, 0]), .init(indices: [0, 0])]
        )
    }

    func testFallsBackThroughExactAlbumResultWhenTrackIsNotTopResult() async throws {
        let provider = FakeAccessibilityProvider(trees: [
            emptyTree,
            searchFieldTree,
            albumSearchResultTree,
            trackTree,
            menuTree
        ])
        let driver = MusicAccessibilityDriver(
            accessibility: provider,
            urlOpener: FakeURLOpener(),
            scripts: MusicScriptReader(runner: NoopRunner()),
            pollInterval: .zero,
            directLookupTimeout: .zero
        )

        let result = try await driver.add(track, to: "试音", timeout: .seconds(1))

        XCTAssertEqual(result, .submitted)
        XCTAssertEqual(provider.pressedPaths.first, .init(indices: [1]))
    }

    func testSearchFallbackRejectsWrongCatalogAndAlbumIDs() async throws {
        let provider = FakeAccessibilityProvider(trees: [
            emptyTree,
            searchFieldTree,
            wrongSearchResultsTree
        ])
        let driver = MusicAccessibilityDriver(
            accessibility: provider,
            urlOpener: FakeURLOpener(),
            scripts: MusicScriptReader(runner: NoopRunner()),
            pollInterval: .milliseconds(1),
            directLookupTimeout: .zero
        )

        let result = try await driver.add(track, to: "试音", timeout: .milliseconds(5))

        XCTAssertEqual(result, .notFound)
        XCTAssertTrue(provider.pressedPaths.isEmpty)
    }

    func testSearchResultMustBeRevalidatedOnAlbumPage() async throws {
        let provider = FakeAccessibilityProvider(trees: [
            emptyTree,
            searchFieldTree,
            topSearchTrackTree,
            emptyTree
        ])
        let driver = MusicAccessibilityDriver(
            accessibility: provider,
            urlOpener: FakeURLOpener(),
            scripts: MusicScriptReader(runner: NoopRunner()),
            pollInterval: .milliseconds(1),
            directLookupTimeout: .zero
        )

        let result = try await driver.add(track, to: "试音", timeout: .milliseconds(8))

        XCTAssertEqual(result, .notFound)
        XCTAssertEqual(provider.pressedPaths, [.init(indices: [0])])
    }

    private var emptyTree: AccessibilityNodeSnapshot { .init(role: "AXWindow") }
    private var searchFieldTree: AccessibilityNodeSnapshot {
        .init(role: "AXWindow", children: [
            .init(identifier: "Music.searchField", role: "AXSearchField")
        ])
    }
    private var topSearchTrackTree: AccessibilityNodeSnapshot {
        .init(role: "AXWindow", children: [
            .init(
                identifier: "Music.shelfItem.TopSearchLockup[id=top-search-section-top-905228611,parentId=top-search-section-top]",
                role: "AXCell"
            )
        ])
    }
    private var albumSearchResultTree: AccessibilityNodeSnapshot {
        .init(role: "AXWindow", children: [
            .init(identifier: "Music.shelfItem.TopSearchLockup[id=top-search-section-top-777,parentId=top-search-section-top]", role: "AXCell"),
            .init(identifier: "Music.shelfItem.SquareLockup[id=square-section-album-905228600,parentId=square-section-album]", role: "AXGroup")
        ])
    }
    private var wrongSearchResultsTree: AccessibilityNodeSnapshot {
        .init(role: "AXWindow", children: [
            .init(identifier: "Music.shelfItem.TopSearchLockup[id=top-search-section-top-905228612,parentId=top-search-section-top]", role: "AXCell"),
            .init(identifier: "Music.shelfItem.SquareLockup[id=square-section-album-905228601,parentId=square-section-album]", role: "AXGroup")
        ])
    }
    private var trackTree: AccessibilityNodeSnapshot {
        .init(role: "AXWindow", children: [
            .init(identifier: "song-905228611", role: "AXRow", children: [
                .init(identifier: "more", role: "AXButton", title: "更多")
            ])
        ])
    }
    private var menuTree: AccessibilityNodeSnapshot {
        .init(role: "AXWindow", children: [
            .init(role: "AXMenu", children: [.init(role: "AXMenuItem", title: "试音")])
        ])
    }
}

private final class FakeAccessibilityProvider: AccessibilityProviding, @unchecked Sendable {
    private var trees: [AccessibilityNodeSnapshot]
    private(set) var pressedPaths: [AccessibilityPath] = []
    private(set) var setValues: [SetValueCall] = []
    private(set) var sentKeys: [MusicKeyStroke] = []
    private(set) var treeReadCount = 0
    init(trees: [AccessibilityNodeSnapshot]) { self.trees = trees }
    func isAuthorized() -> Bool { true }
    func musicTree() throws -> AccessibilityNodeSnapshot {
        treeReadCount += 1
        return trees.count > 1 ? trees.removeFirst() : trees[0]
    }
    func press(path: AccessibilityPath) throws { pressedPaths.append(path) }
    func setValue(_ value: String, path: AccessibilityPath) throws {
        setValues.append(.init(value: value, path: path))
    }
    func send(_ keyStroke: MusicKeyStroke) throws { sentKeys.append(keyStroke) }
}

private struct SetValueCall: Equatable {
    let value: String
    let path: AccessibilityPath
}

private final class FakeURLOpener: URLOpening, @unchecked Sendable {
    private(set) var openedURLs: [URL] = []
    func openInMusic(_ url: URL) async throws { openedURLs.append(url) }
}

private actor NoopRunner: ProcessRunning {
    func run(executable: URL, arguments: [String], stdin: Data?) throws -> ProcessResult {
        .init(exitCode: 0, stdout: Data("null".utf8), stderr: Data())
    }
}
