import XCTest
@testable import PlaylistCore

final class TextNormalizationTests: XCTestCase {
    func testEquivalentUnicodeAndWhitespaceProduceSameKey() {
        let composed = TrackKey(name: " Caf\u{00E9}\u{3000}Live ", artist: "THE  BAND")
        let decomposed = TrackKey(name: "cafe\u{0301}   live", artist: "the band")
        XCTAssertEqual(composed, decomposed)
    }

    func testCommonChineseAndASCIIPunctuationIsIgnored() {
        XCTAssertEqual(
            TrackKey(name: "月满西楼（现场）！", artist: "歌手：甲"),
            TrackKey(name: "月满西楼现场", artist: "歌手甲")
        )
    }

    func testSameTitleWithDifferentArtistsIsNotDuplicate() {
        XCTAssertNotEqual(
            TrackKey(name: "Hallelujah", artist: "Jeff Buckley"),
            TrackKey(name: "Hallelujah", artist: "Leonard Cohen")
        )
    }

    func testSuccessfulAndDuplicateOnlyReportExitsZero() {
        let report = WorkflowReport(results: [
            .init(track: nil, status: .added, message: "已添加"),
            .init(track: nil, status: .skippedDuplicate, message: "已跳过重复项")
        ])
        XCTAssertEqual(report.exitCode, 0)
    }

    func testAnyFailureStatusExitsFive() {
        let failures: [TrackOperationStatus] = [
            .notFound, .permissionDenied, .playlistMissing, .verificationFailed, .failed
        ]
        for failure in failures {
            let report = WorkflowReport(results: [
                .init(track: nil, status: .added, message: "已添加"),
                .init(track: nil, status: failure, message: "失败")
            ])
            XCTAssertEqual(report.exitCode, 5, "状态 \(failure) 应返回失败退出码")
        }
    }
}
