import Foundation
import Darwin
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

    func testRejectsSymlinkAndGroupOrOtherAccessibleReceiptDirectories() throws {
        let target = try temporaryDirectory()
        let symlink = target.deletingLastPathComponent()
            .appendingPathComponent("am-playlist-receipts-link-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: symlink)
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        XCTAssertThrowsError(try FileRemovalReceiptStore(directory: symlink))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o750], ofItemAtPath: target.path
        )
        XCTAssertThrowsError(try FileRemovalReceiptStore(directory: target))
    }

    func testRejectsDirectoryNotOwnedByEffectiveUserAtValidationBoundary() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNoThrow(try FileRemovalReceiptStore(directory: directory))
        XCTAssertThrowsError(try FileRemovalReceiptStore(
            directory: directory, effectiveUserID: geteuid() &+ 1
        ))
    }

    func testReceiptFileIsCreatedWithOwnerOnly0600Permissions() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FileRemovalReceiptStore(directory: directory)

        let token = await store.issue(receiptArtifact(snapshot: "snapshot"))
        var metadata = stat()
        XCTAssertEqual(lstat(directory.appendingPathComponent("\(token).json").path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & 0o777, 0o600)
        XCTAssertEqual(metadata.st_uid, geteuid())
    }

    func testOperationsFailClosedIfDirectoryPermissionsBecomeUnsafe() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FileRemovalReceiptStore(directory: directory)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: directory.path
        )

        let token = await store.issue(receiptArtifact(snapshot: "snapshot"))

        XCTAssertTrue(token.isEmpty)
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty)
    }

    func testLockedReceiptCannotBeConsumedAndOriginalRemainsAvailable() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = receiptArtifact(snapshot: "snapshot")
        let store = try FileRemovalReceiptStore(directory: directory)
        let token = await store.issue(artifact)
        let path = directory.appendingPathComponent("\(token).json").path
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
        }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)

        let consumed = await store.consume(token: token, matching: artifact)
        let stored = await store.receipt(for: token)

        XCTAssertFalse(consumed)
        XCTAssertEqual(stored, artifact)
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
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }
}
