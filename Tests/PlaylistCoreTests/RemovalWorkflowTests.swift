import XCTest
@testable import PlaylistCore

final class RemovalWorkflowTests: XCTestCase {
    private let target = RemovalTrack(databaseID: "101", name: "被遗忘的时光", artist: "蔡琴")
    private let other = RemovalTrack(databaseID: "102", name: "Hotel California", artist: "Eagles")

    func testDryRunWithExactMatchDoesNotWrite() async {
        let client = RemovalFakeMusicAppClient(playlist: .init(name: "试音", tracks: [target.playlistTrack]))
        let receiptStore = InMemoryRemovalReceiptStore()

        let report = await RemovalWorkflow(client: client, receiptStore: receiptStore).run(
            document: .init(playlist: "试音", tracks: [target]), options: .init(dryRun: true)
        )

        XCTAssertEqual(report.results.map(\.status), [.wouldRemove])
        XCTAssertNotNil(report.removalReceiptToken)
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 0)
    }

    func testReceiptTokenRejectsMissingReceiptForgedTokenAndReplay() async throws {
        let document = RemovalInputDocument(playlist: "试音", tracks: [target])
        let snapshot = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack])
        let receiptStore = InMemoryRemovalReceiptStore()
        let dryRun = await RemovalWorkflow(
            client: RemovalFakeMusicAppClient(playlist: snapshot), receiptStore: receiptStore
        ).run(document: document, options: .init(dryRun: true))
        let receiptToken = try XCTUnwrap(dryRun.removalReceiptToken)

        let missingReceiptClient = RemovalFakeMusicAppClient(playlist: snapshot)
        _ = await RemovalWorkflow(
            client: missingReceiptClient, receiptStore: InMemoryRemovalReceiptStore()
        ).run(document: document, options: .init(approval: .init(approved: true, receiptToken: receiptToken)))

        let forgedTokenClient = RemovalFakeMusicAppClient(playlist: snapshot)
        _ = await RemovalWorkflow(
            client: forgedTokenClient, receiptStore: receiptStore
        ).run(document: document, options: .init(approval: .init(approved: true, receiptToken: "伪造收据")))

        let unapprovedClient = RemovalFakeMusicAppClient(playlist: snapshot)
        _ = await RemovalWorkflow(
            client: unapprovedClient, receiptStore: receiptStore
        ).run(document: document, options: .init(approval: .init(approved: false, receiptToken: receiptToken)))

        let approvedClient = RemovalFakeMusicAppClient(
            playlist: snapshot, verificationSnapshots: [.init(name: "试音", tracks: [])]
        )
        let approvedReport = await RemovalWorkflow(
            client: approvedClient, receiptStore: receiptStore
        ).run(document: document, options: .init(approval: .init(approved: true, receiptToken: receiptToken)))

        let replayClient = RemovalFakeMusicAppClient(playlist: snapshot)
        _ = await RemovalWorkflow(
            client: replayClient, receiptStore: receiptStore
        ).run(document: document, options: .init(approval: .init(approved: true, receiptToken: receiptToken)))

        let missingReceiptWrites = await missingReceiptClient.removeCount
        let forgedTokenWrites = await forgedTokenClient.removeCount
        let unapprovedWrites = await unapprovedClient.removeCount
        let approvedWrites = await approvedClient.removeCount
        let replayWrites = await replayClient.removeCount
        XCTAssertEqual(missingReceiptWrites, 0)
        XCTAssertEqual(forgedTokenWrites, 0)
        XCTAssertEqual(unapprovedWrites, 0)
        XCTAssertEqual(approvedReport.results.map(\.status), [.removed])
        XCTAssertEqual(approvedWrites, 1)
        XCTAssertEqual(replayWrites, 0)
    }

    func testReceiptRejectsAnyPlaylistSnapshotChangeBeforeWriting() async throws {
        let document = RemovalInputDocument(playlist: "试音", tracks: [target])
        let drySnapshot = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack])
        let receiptStore = InMemoryRemovalReceiptStore()
        let dryRun = await RemovalWorkflow(
            client: RemovalFakeMusicAppClient(playlist: drySnapshot), receiptStore: receiptStore
        ).run(document: document, options: .init(dryRun: true))
        let receiptToken = try XCTUnwrap(dryRun.removalReceiptToken)
        let changedSnapshot = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack, other.playlistTrack])
        let actualClient = RemovalFakeMusicAppClient(playlist: changedSnapshot)

        let report = await RemovalWorkflow(client: actualClient, receiptStore: receiptStore).run(
            document: document, options: .init(approval: .init(approved: true, receiptToken: receiptToken))
        )

        XCTAssertEqual(report.results.map(\.status), [.failed])
        let removeCount = await actualClient.removeCount
        XCTAssertEqual(removeCount, 0)
    }

    func testReceiptFromMissingDryRunCannotAuthorizeLaterUniqueMatch() async throws {
        let document = RemovalInputDocument(playlist: "试音", tracks: [target])
        let missingSnapshot = PlaylistSnapshot(
            name: "试音", tracks: [.init(name: target.name, artist: "其他艺人", databaseID: target.databaseID)]
        )
        let receiptStore = InMemoryRemovalReceiptStore()
        let dryRun = await RemovalWorkflow(
            client: RemovalFakeMusicAppClient(playlist: missingSnapshot), receiptStore: receiptStore
        ).run(document: document, options: .init(dryRun: true))
        let receiptToken = try XCTUnwrap(dryRun.removalReceiptToken)
        let actualClient = RemovalFakeMusicAppClient(playlist: .init(name: "试音", tracks: [target.playlistTrack]))

        let report = await RemovalWorkflow(client: actualClient, receiptStore: receiptStore).run(
            document: document, options: .init(approval: .init(approved: true, receiptToken: receiptToken))
        )

        XCTAssertEqual(report.results.map(\.status), [.failed])
        let removeCount = await actualClient.removeCount
        XCTAssertEqual(removeCount, 0)
    }

    func testReceiptFromAmbiguousDryRunCannotAuthorizeLaterUniqueMatch() async throws {
        let document = RemovalInputDocument(playlist: "试音", tracks: [target])
        let ambiguousSnapshot = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack, target.playlistTrack])
        let receiptStore = InMemoryRemovalReceiptStore()
        let dryRun = await RemovalWorkflow(
            client: RemovalFakeMusicAppClient(playlist: ambiguousSnapshot), receiptStore: receiptStore
        ).run(document: document, options: .init(dryRun: true))
        let receiptToken = try XCTUnwrap(dryRun.removalReceiptToken)
        let actualClient = RemovalFakeMusicAppClient(playlist: .init(name: "试音", tracks: [target.playlistTrack]))

        let report = await RemovalWorkflow(client: actualClient, receiptStore: receiptStore).run(
            document: document, options: .init(approval: .init(approved: true, receiptToken: receiptToken))
        )

        XCTAssertEqual(report.results.map(\.status), [.failed])
        let removeCount = await actualClient.removeCount
        XCTAssertEqual(removeCount, 0)
    }

    func testVerificationReadFailureRequiresRecoveryBeforeLaterWrite() async throws {
        let document = RemovalInputDocument(playlist: "试音", tracks: [target, other])
        let initial = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack, other.playlistTrack])
        let recovered = PlaylistSnapshot(name: "试音", tracks: [other.playlistTrack])
        let afterSecondRemoval = PlaylistSnapshot(name: "试音", tracks: [])
        let dryRunClient = RemovalFakeMusicAppClient(playlist: initial)
        let receiptStore = InMemoryRemovalReceiptStore()
        let dryRunReport = await RemovalWorkflow(client: dryRunClient, receiptStore: receiptStore).run(
            document: document, options: .init(dryRun: true)
        )
        let receiptToken = try XCTUnwrap(dryRunReport.removalReceiptToken)
        let client = RemovalFakeMusicAppClient(
            playlist: initial,
            playlistOutcomes: [.snapshot(initial), .failure, .snapshot(recovered), .snapshot(afterSecondRemoval)]
        )

        let report = await RemovalWorkflow(client: client, receiptStore: receiptStore).run(
            document: document,
            options: .init(approval: .init(approved: true, receiptToken: receiptToken))
        )

        XCTAssertEqual(report.results.map(\.status), [.verificationFailed, .removed])
        let playlistReadCount = await client.playlistReadCount
        let removeCount = await client.removeCount
        XCTAssertEqual(playlistReadCount, 4)
        XCTAssertEqual(removeCount, 2)
    }

    func testInputDocumentDecodesThreeExactFieldsUsingDatabaseId() throws {
        let data = Data(#"{"playlist":"试音","tracks":[{"databaseId":"101","name":"被遗忘的时光","artist":"蔡琴"}]}"#.utf8)

        let document = try JSONDecoder().decode(RemovalInputDocument.self, from: data)

        XCTAssertEqual(document, .init(playlist: "试音", tracks: [target]))
    }

    func testOnlyExactDatabaseIDNameAndArtistMatchIsRemoved() async throws {
        let before = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack])
        let after = PlaylistSnapshot(name: "试音", tracks: [])
        let client = RemovalFakeMusicAppClient(playlist: before, verificationSnapshots: [after])
        let document = RemovalInputDocument(playlist: "试音", tracks: [target])
        let (receiptStore, approval) = try await approval(for: document, snapshot: before)

        let report = await RemovalWorkflow(client: client, receiptStore: receiptStore).run(
            document: document, options: .init(approval: approval)
        )

        XCTAssertEqual(report.results.map(\.status), [.removed])
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 1)
    }

    func testMissingOrAmbiguousMatchDoesNotWrite() async throws {
        let missing = PlaylistTrack(name: target.name, artist: "其他艺人", databaseID: target.databaseID)
        let ambiguous = PlaylistTrack(name: other.name, artist: other.artist, databaseID: other.databaseID)
        let snapshot = PlaylistSnapshot(name: "试音", tracks: [missing, ambiguous, ambiguous])
        let client = RemovalFakeMusicAppClient(playlist: snapshot)
        let document = RemovalInputDocument(playlist: "试音", tracks: [target, other])
        let (receiptStore, approval) = try await approval(for: document, snapshot: snapshot)

        let report = await RemovalWorkflow(client: client, receiptStore: receiptStore).run(
            document: document, options: .init(approval: approval)
        )

        XCTAssertEqual(report.results.map(\.status), [.notFound, .notFound])
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 0)
    }

    func testExistingDatabaseIDAfterWriteReturnsVerificationFailure() async throws {
        let before = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack])
        let client = RemovalFakeMusicAppClient(playlist: before, verificationSnapshots: [before])
        let document = RemovalInputDocument(playlist: "试音", tracks: [target])
        let (receiptStore, approval) = try await approval(for: document, snapshot: before)

        let report = await RemovalWorkflow(client: client, receiptStore: receiptStore).run(
            document: document, options: .init(approval: approval)
        )

        XCTAssertEqual(report.results.map(\.status), [.verificationFailed])
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 1)
    }

    func testFailedItemDoesNotPreventLaterExactRemoval() async throws {
        let before = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack, other.playlistTrack])
        let afterSecondRemoval = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack])
        let client = RemovalFakeMusicAppClient(
            playlist: before,
            removeFailures: [true, false],
            verificationSnapshots: [afterSecondRemoval]
        )
        let document = RemovalInputDocument(playlist: "试音", tracks: [target, other])
        let (receiptStore, approval) = try await approval(for: document, snapshot: before)

        let report = await RemovalWorkflow(client: client, receiptStore: receiptStore).run(
            document: document, options: .init(approval: approval)
        )

        XCTAssertEqual(report.results.map(\.status), [.failed, .removed])
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 2)
    }

    private func approval(
        for document: RemovalInputDocument,
        snapshot: PlaylistSnapshot
    ) async throws -> (InMemoryRemovalReceiptStore, RemovalApproval) {
        let client = RemovalFakeMusicAppClient(playlist: snapshot)
        let receiptStore = InMemoryRemovalReceiptStore()
        let report = await RemovalWorkflow(client: client, receiptStore: receiptStore).run(
            document: document, options: .init(dryRun: true)
        )
        return (receiptStore, .init(approved: true, receiptToken: try XCTUnwrap(report.removalReceiptToken)))
    }
}

private extension RemovalTrack {
    var playlistTrack: PlaylistTrack {
        PlaylistTrack(name: name, artist: artist, databaseID: databaseID)
    }
}

private enum RemovalFakeError: LocalizedError {
    case removalFailed
    case playlistReadFailed

    var errorDescription: String? {
        switch self {
        case .removalFailed: "模拟删除失败"
        case .playlistReadFailed: "模拟播放列表读取失败"
        }
    }
}

private enum PlaylistReadOutcome {
    case snapshot(PlaylistSnapshot?)
    case failure
}

private actor RemovalFakeMusicAppClient: MusicAppClient {
    private var initialPlaylist: PlaylistSnapshot?
    private var verificationSnapshots: [PlaylistSnapshot]
    private var removeFailures: [Bool]
    private var playlistOutcomes: [PlaylistReadOutcome]
    private(set) var removeCount = 0
    private(set) var playlistReadCount = 0

    init(
        playlist: PlaylistSnapshot?,
        removeFailures: [Bool] = [],
        verificationSnapshots: [PlaylistSnapshot] = [],
        playlistOutcomes: [PlaylistReadOutcome] = []
    ) {
        self.initialPlaylist = playlist
        self.removeFailures = removeFailures
        self.verificationSnapshots = verificationSnapshots
        self.playlistOutcomes = playlistOutcomes
    }

    func accessibilityAuthorized() -> Bool { true }

    func playlist(named: String) throws -> PlaylistSnapshot? {
        playlistReadCount += 1
        if !playlistOutcomes.isEmpty {
            switch playlistOutcomes.removeFirst() {
            case let .snapshot(snapshot): return snapshot
            case .failure: throw RemovalFakeError.playlistReadFailed
            }
        }
        if playlistReadCount == 1 { return initialPlaylist }
        if !verificationSnapshots.isEmpty { return verificationSnapshots.removeFirst() }
        return initialPlaylist
    }

    func createPlaylist(named: String) {}

    func add(_ track: CatalogTrack, to playlist: String, timeout: Duration) throws -> AddTrackOutcome { .submitted }

    func remove(_ track: RemovalTrack, from playlist: String) throws {
        removeCount += 1
        if !removeFailures.isEmpty, removeFailures.removeFirst() { throw RemovalFakeError.removalFailed }
    }

    func play(track: CatalogTrack, in playlist: String) {}
}
