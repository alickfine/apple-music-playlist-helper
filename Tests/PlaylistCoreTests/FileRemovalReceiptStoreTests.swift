import Foundation
import XCTest
@testable import PlaylistCore

final class FileRemovalReceiptStoreTests: XCTestCase {
    func testReceiptPersistsAcrossStoreInstancesAndCanOnlyBeConsumedOnce() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = receiptArtifact(snapshot: "snapshot-a")
        let issuer = try FileRemovalReceiptStore(directory: directory)

        let token = await issuer.issue(artifact)
        let consumer = try FileRemovalReceiptStore(directory: directory)
        let stored = await consumer.receipt(for: token)
        let consumed = await consumer.consume(token: token, matching: artifact)
        let replayedReceipt = await issuer.receipt(for: token)
        let replayed = await issuer.consume(token: token, matching: artifact)

        XCTAssertFalse(token.isEmpty)
        XCTAssertEqual(stored, artifact)
        XCTAssertTrue(consumed)
        XCTAssertNil(replayedReceipt)
        XCTAssertFalse(replayed)
    }

    func testMismatchedArtifactDoesNotConsumeReceipt() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = receiptArtifact(snapshot: "snapshot-a")
        let store = try FileRemovalReceiptStore(directory: directory)
        let token = await store.issue(expected)
        let mismatchConsumed = await store.consume(
            token: token, matching: receiptArtifact(snapshot: "snapshot-b")
        )
        let restored = await store.receipt(for: token)

        XCTAssertFalse(mismatchConsumed)
        XCTAssertEqual(restored, expected)
    }

    func testConcurrentConsumersCannotReplayReceiptAcrossStoreInstances() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = receiptArtifact(snapshot: "snapshot-a")
        let issuer = try FileRemovalReceiptStore(directory: directory)
        let first = try FileRemovalReceiptStore(directory: directory)
        let second = try FileRemovalReceiptStore(directory: directory)
        let token = await issuer.issue(artifact)

        async let firstResult = first.consume(token: token, matching: artifact)
        async let secondResult = second.consume(token: token, matching: artifact)
        let results = await [firstResult, secondResult]

        XCTAssertEqual(results.filter { $0 }.count, 1)
    }

    func testForgedTokenCannotEscapeReceiptDirectory() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FileRemovalReceiptStore(directory: directory)
        let receipt = await store.receipt(for: "../伪造")
        let consumed = await store.consume(
            token: "../伪造", matching: receiptArtifact(snapshot: "snapshot")
        )

        XCTAssertNil(receipt)
        XCTAssertFalse(consumed)
    }

    private func receiptArtifact(snapshot: String) -> RemovalReceiptArtifact {
        let track = RemovalTrack(databaseID: "123", name: "测试曲目", artist: "测试艺人")
        return RemovalReceiptArtifact(
            playlistName: "试音",
            tracks: [track],
            playlistSnapshotFingerprint: snapshot,
            matchResults: [.init(track: track, exactMatchCount: 1)],
            wouldRemoveTracks: [track]
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("am-playlist-receipts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
