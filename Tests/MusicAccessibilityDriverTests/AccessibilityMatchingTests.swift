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
}
