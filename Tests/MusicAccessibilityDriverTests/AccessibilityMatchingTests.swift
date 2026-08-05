import XCTest
@testable import MusicAccessibilityDriver

final class AccessibilityMatchingTests: XCTestCase {
    private let tree = AccessibilityNodeSnapshot(
        identifier: "root", role: "AXWindow", title: nil, description: nil,
        children: [
            .init(identifier: "song-905228612", role: "AXRow", title: "被遗忘的时光 近似项", description: nil, children: [
                .init(identifier: "more-near", role: "AXButton", title: "更多", description: nil)
            ]),
            .init(identifier: "song-905228611", role: "AXRow", title: "被遗忘的时光", description: nil, children: [
                .init(identifier: "more-exact", role: "AXButton", title: "更多", description: nil)
            ]),
            .init(identifier: "menu", role: "AXMenu", title: nil, description: nil, children: [
                .init(identifier: "p1", role: "AXMenuItem", title: "试音增强", description: nil),
                .init(identifier: "p2", role: "AXMenuItem", title: "试音", description: nil)
            ])
        ]
    )

    func testFindsMoreButtonOnlyUnderExactCatalogIDRow() {
        XCTAssertEqual(AccessibilityMatcher.trackMoreButton(catalogID: "905228611", in: tree), .init(indices: [1, 0]))
    }

    func testDoesNotTreatLongerNumericTokenAsCatalogID() {
        XCTAssertNil(AccessibilityMatcher.trackMoreButton(catalogID: "90522861", in: tree))
    }

    func testMissingCatalogIDReturnsNil() {
        XCTAssertNil(AccessibilityMatcher.trackMoreButton(catalogID: "999999999", in: tree))
    }

    func testPlaylistMenuItemRequiresExactName() {
        XCTAssertEqual(AccessibilityMatcher.playlistMenuItem(named: "试音", in: tree), .init(indices: [2, 1]))
        XCTAssertNil(AccessibilityMatcher.playlistMenuItem(named: "试", in: tree))
    }

    func testFindsExactTrackContainerAndSidebarPlaylistForBridge() {
        let dragTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(role: "AXRow", value: "Apple Music Skill 测试", children: []),
            .init(identifier: "track-lockup-905228605-905228635", role: "AXGroup", children: [
                .init(role: "AXStaticText", value: "8 渡口 3:47"),
                .init(role: "AXButton", title: "更多")
            ])
        ])

        XCTAssertEqual(AccessibilityMatcher.trackContainer(catalogID: "905228635", in: dragTree), .init(indices: [1]))
        XCTAssertEqual(AccessibilityMatcher.sidebarPlaylistRow(named: "Apple Music Skill 测试", in: dragTree), .init(indices: [0]))
        XCTAssertNil(AccessibilityMatcher.sidebarPlaylistRow(named: "Apple Music Skill", in: dragTree))

        let nativeTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(role: "AXStaticText", title: "Apple Music Skill 测试")
        ])
        XCTAssertEqual(AccessibilityMatcher.sidebarPlaylistRow(named: "Apple Music Skill 测试", in: nativeTree), .init(indices: [0]))
    }

    func testFindsMenuForStructuredCancellation() {
        let menuTree = AccessibilityNodeSnapshot(role: "AXApplication", children: [
            .init(role: "AXMenu")
        ])
        let menuBarTree = AccessibilityNodeSnapshot(role: "AXApplication", children: [
            .init(role: "AXMenuBar", children: [.init(role: "AXMenu")])
        ])
        XCTAssertEqual(AccessibilityMatcher.menu(in: menuTree), .init(indices: [0]))
        XCTAssertNil(AccessibilityMatcher.menu(in: menuBarTree))
    }

    func testFindsSearchFieldByRole() {
        let searchTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(identifier: "unrelated", role: "AXTextField"),
            .init(identifier: "Music.searchField", role: "AXSearchField")
        ])

        XCTAssertEqual(AccessibilityMatcher.searchField(in: searchTree), .init(indices: [1]))
    }

    func testRequiresSearchScopeBeforeTreatingSearchScreenAsReady() {
        let staleAlbumTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(identifier: "Music.searchField", role: "AXSearchField")
        ])
        let scopeOnlyTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(identifier: "Music.searchField", role: "AXSearchField"),
            .init(identifier: "UIA.Music.Search.Scope", role: "AXGroup")
        ])
        let readySearchTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(identifier: "Music.searchField", role: "AXSearchField"),
            .init(identifier: "Music.shelfItem.SearchLandingBrickLockup[id=brick-lockup-1]", role: "AXCell")
        ])

        XCTAssertNil(AccessibilityMatcher.readySearchField(in: staleAlbumTree))
        XCTAssertNil(AccessibilityMatcher.readySearchField(in: scopeOnlyTree))
        XCTAssertEqual(AccessibilityMatcher.readySearchField(in: readySearchTree), .init(indices: [0]))
    }

    func testFindsOnlyExactSidebarSearchRow() {
        let navigationTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(role: "AXRow", title: "搜索增强"),
            .init(role: "AXRow", title: "搜索"),
            .init(role: "AXRow", title: "主页")
        ])

        XCTAssertEqual(AccessibilityMatcher.sidebarSearchRow(in: navigationTree), .init(indices: [1]))
    }

    func testFindsOnlyExactTopSearchCatalogID() {
        let searchTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(identifier: "Music.shelfItem.TopSearchLockup[id=top-search-section-top-90522863,parentId=top-search-section-top]", role: "AXCell"),
            .init(identifier: "Music.shelfItem.TopSearchLockup[id=top-search-section-top-905228635,parentId=top-search-section-top]", role: "AXCell")
        ])

        XCTAssertEqual(
            AccessibilityMatcher.topSearchResult(catalogID: "905228635", in: searchTree),
            .init(indices: [1])
        )
        XCTAssertNil(AccessibilityMatcher.topSearchResult(catalogID: "9052286", in: searchTree))
    }

    func testFindsExactAlbumInTopOrSquareSearchResult() {
        let topTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(identifier: "Music.shelfItem.TopSearchLockup[id=top-search-section-top-905228605,parentId=top-search-section-top]", role: "AXCell")
        ])
        let squareTree = AccessibilityNodeSnapshot(role: "AXWindow", children: [
            .init(identifier: "Music.shelfItem.SquareLockup[id=square-section-album-905228605,parentId=square-section-album]", role: "AXGroup")
        ])

        XCTAssertEqual(AccessibilityMatcher.albumSearchResult(albumID: "905228605", in: topTree), .init(indices: [0]))
        XCTAssertEqual(AccessibilityMatcher.albumSearchResult(albumID: "905228605", in: squareTree), .init(indices: [0]))
        XCTAssertNil(AccessibilityMatcher.albumSearchResult(albumID: "90522860", in: squareTree))
    }
}
