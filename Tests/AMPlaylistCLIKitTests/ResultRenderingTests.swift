import Foundation
import XCTest
@testable import AMPlaylistCLIKit
import PlaylistCore

final class ResultRenderingTests: XCTestCase {
    private let track = CatalogTrack(
        id: "905228611", name: "被遗忘的时光", artist: "蔡琴",
        url: URL(string: "https://music.apple.com/cn/album/example/1?i=905228611")!
    )

    func testTextOutputUsesChinesePerTrackStatus() throws {
        let report = WorkflowReport(results: [
            .init(track: track, status: .skippedDuplicate, message: "播放列表中已存在，已跳过。")
        ])
        let output = try ResultRenderer.render(report: report, json: false)
        XCTAssertTrue(output.contains("已跳过重复项"))
        XCTAssertTrue(output.contains("被遗忘的时光 — 蔡琴"))
    }

    func testJSONOutputUsesMachineStatusAndContainsNoOtherTracks() throws {
        let report = WorkflowReport(results: [
            .init(track: track, status: .skippedDuplicate, message: "播放列表中已存在，已跳过。")
        ])
        let output = try ResultRenderer.render(report: report, json: true)
        XCTAssertTrue(output.contains(#""status":"skipped_duplicate""#))
        XCTAssertFalse(output.contains("Hotel California"))
    }
}
