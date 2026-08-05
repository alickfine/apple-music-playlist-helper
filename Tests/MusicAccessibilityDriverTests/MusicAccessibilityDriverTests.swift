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

    func testCannotCompletePressIsAcceptedOnlyWhenTheExpectedMenuPostconditionExists() async throws {
        let provider = FakeAccessibilityProvider(
            trees: [trackTree, menuTree],
            pressErrors: [
                .init(indices: [0, 0]): AccessibilityDriverError.pressFailed(-25204, "more"),
                .init(indices: [0, 0, 0]): AccessibilityDriverError.pressFailed(-25204, "playlist")
            ]
        )
        let driver = MusicAccessibilityDriver(
            accessibility: provider, urlOpener: FakeURLOpener(), scripts: MusicScriptReader(runner: NoopRunner()), pollInterval: .zero
        )

        let result = try await driver.add(track, to: "试音", timeout: .seconds(1))

        XCTAssertEqual(result, .submitted)
        XCTAssertEqual(provider.pressedPaths.count, 2)
    }

    func testFallsBackToExactAXValidatedScriptBridgeWhenEmptyPlaylistIsMissingFromMenu() async throws {
        let dragTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(role: "AXRow", value: "试音"),
            .init(identifier: "track-lockup-905228600-905228611", role: "AXGroup", children: [
                .init(role: "AXButton", title: "更多")
            ])
        ])
        let provider = FakeAccessibilityProvider(trees: [trackTree, missingPlaylistMenuTree, dragTree])
        let opener = FakeURLOpener()
        let driver = MusicAccessibilityDriver(
            accessibility: provider, urlOpener: opener, scripts: MusicScriptReader(runner: NoopRunner()), pollInterval: .zero
        )

        let result = try await driver.add(track, to: "试音", timeout: .seconds(1))

        XCTAssertEqual(result, .submitted)
        XCTAssertEqual(provider.cancelledPaths, [.init(indices: [0])])
        XCTAssertEqual(opener.openedURLs, [track.url, track.url])
    }

    func testStaleMenuCancelFallsBackToEscapeBeforeExactBridge() async throws {
        let dragTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(role: "AXRow", value: "试音"),
            .init(identifier: "track-lockup-905228600-905228611", role: "AXGroup", children: [
                .init(role: "AXButton", title: "更多")
            ])
        ])
        let provider = FakeAccessibilityProvider(
            trees: [trackTree, missingPlaylistMenuTree, dragTree],
            cancelError: AccessibilityDriverError.invalidPath
        )
        let driver = MusicAccessibilityDriver(
            accessibility: provider, urlOpener: FakeURLOpener(), scripts: MusicScriptReader(runner: NoopRunner()), pollInterval: .zero
        )

        let result = try await driver.add(track, to: "试音", timeout: .seconds(1))

        XCTAssertEqual(result, .submitted)
        XCTAssertEqual(provider.sentKeys, [.escape])
    }

    func testSuccessfulCancelStillUsesEscapeWhenMenuPostconditionRemainsOpenBeforeBridge() async throws {
        let dragTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(role: "AXStaticText", value: "试音"),
            .init(identifier: "track-lockup-905228600-905228611", role: "AXGroup", children: [
                .init(role: "AXButton", title: "更多")
            ])
        ])
        let provider = FakeAccessibilityProvider(trees: [
            trackTree, missingPlaylistMenuTree, missingPlaylistMenuTree, dragTree
        ])
        let driver = MusicAccessibilityDriver(
            accessibility: provider, urlOpener: FakeURLOpener(), scripts: MusicScriptReader(runner: NoopRunner()), pollInterval: .zero
        )

        let result = try await driver.add(track, to: "试音", timeout: .seconds(1))

        XCTAssertEqual(result, .submitted)
        XCTAssertEqual(provider.sentKeys, [.escape])
    }

    func testProviderRecordsExactSearchInteraction() throws {
        let provider = FakeAccessibilityProvider(trees: [emptyTree])
        let searchPath = AccessibilityPath(indices: [0, 1])

        try provider.setValue("被遗忘的时光 蔡琴", path: searchPath)
        try provider.send(.commandF)
        try provider.send(.returnKey)

        XCTAssertEqual(
            provider.setValues,
            [.init(value: "被遗忘的时光 蔡琴", path: searchPath)]
        )
        XCTAssertEqual(provider.sentKeys, [.commandF, .returnKey])
    }

    func testFallsBackToExactSearchResultAndRevalidatesAlbumTrack() async throws {
        let provider = FakeAccessibilityProvider(trees: [
            emptyTree,
            sidebarSearchTree,
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
        XCTAssertEqual(provider.sentKeys, [.returnKey])
        XCTAssertEqual(provider.setValues, [.init(value: "被遗忘的时光 蔡琴", path: .init(indices: [0]))])
        XCTAssertEqual(
            provider.pressedPaths,
            [.init(indices: [0]), .init(indices: [0]), .init(indices: [0, 0]), .init(indices: [0, 0])]
        )
    }

    func testFallsBackThroughExactAlbumResultWhenTrackIsNotTopResult() async throws {
        let provider = FakeAccessibilityProvider(trees: [
            emptyTree,
            sidebarSearchTree,
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
        XCTAssertEqual(provider.pressedPaths.dropFirst().first, .init(indices: [1]))
    }

    func testSearchFallbackRejectsWrongCatalogAndAlbumIDs() async throws {
        let provider = FakeAccessibilityProvider(trees: [
            emptyTree,
            sidebarSearchTree,
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
        XCTAssertEqual(provider.pressedPaths, [.init(indices: [0])])
    }

    func testSearchResultMustBeRevalidatedOnAlbumPage() async throws {
        let provider = FakeAccessibilityProvider(trees: [
            emptyTree,
            sidebarSearchTree,
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
        XCTAssertEqual(provider.pressedPaths, [.init(indices: [0]), .init(indices: [0])])
    }

    private var emptyTree: AccessibilityNodeSnapshot { .init(role: "AXWindow") }
    private var searchFieldTree: AccessibilityNodeSnapshot {
        .init(role: "AXWindow", children: [
            .init(identifier: "Music.searchField", role: "AXSearchField"),
            .init(identifier: "Music.shelfItem.SearchLandingBrickLockup[id=brick-lockup-1]", role: "AXCell")
        ])
    }
    private var sidebarSearchTree: AccessibilityNodeSnapshot {
        .init(role: "AXWindow", children: [
            .init(role: "AXRow", title: "搜索")
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
    private var missingPlaylistMenuTree: AccessibilityNodeSnapshot {
        .init(role: "AXWindow", children: [.init(role: "AXMenu")])
    }
}

private final class FakeAccessibilityProvider: AccessibilityProviding, @unchecked Sendable {
    private var trees: [AccessibilityNodeSnapshot]
    private var pressErrors: [AccessibilityPath: AccessibilityDriverError]
    private let cancelError: AccessibilityDriverError?
    private(set) var pressedPaths: [AccessibilityPath] = []
    private(set) var setValues: [SetValueCall] = []
    private(set) var sentKeys: [MusicKeyStroke] = []
    private(set) var cancelledPaths: [AccessibilityPath] = []
    private(set) var treeReadCount = 0
    init(
        trees: [AccessibilityNodeSnapshot],
        pressErrors: [AccessibilityPath: AccessibilityDriverError] = [:],
        cancelError: AccessibilityDriverError? = nil
    ) {
        self.trees = trees
        self.pressErrors = pressErrors
        self.cancelError = cancelError
    }
    func isAuthorized() -> Bool { true }
    func musicTree() throws -> AccessibilityNodeSnapshot {
        treeReadCount += 1
        return trees.count > 1 ? trees.removeFirst() : trees[0]
    }
    func press(path: AccessibilityPath) throws {
        pressedPaths.append(path)
        if let error = pressErrors.removeValue(forKey: path) { throw error }
    }
    func setValue(_ value: String, path: AccessibilityPath) throws {
        setValues.append(.init(value: value, path: path))
    }
    func send(_ keyStroke: MusicKeyStroke) throws { sentKeys.append(keyStroke) }
    func cancel(path: AccessibilityPath) throws {
        cancelledPaths.append(path)
        if let cancelError { throw cancelError }
    }
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
