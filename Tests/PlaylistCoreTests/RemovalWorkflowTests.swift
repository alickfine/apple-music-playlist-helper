import XCTest
@testable import PlaylistCore

final class RemovalWorkflowTests: XCTestCase {
    private let target = RemovalTrack(databaseID: "101", name: "被遗忘的时光", artist: "蔡琴")
    private let other = RemovalTrack(databaseID: "102", name: "Hotel California", artist: "Eagles")

    func testDryRunWithExactMatchDoesNotWrite() async {
        let client = RemovalFakeMusicAppClient(playlist: .init(name: "试音", tracks: [target.playlistTrack]))

        let report = await RemovalWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [target]), options: .init(dryRun: true)
        )

        XCTAssertEqual(report.results.map(\.status), [.wouldRemove])
        XCTAssertNotNil(report.removalConfirmationFingerprint)
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 0)
    }

    func testActualRemovalRequiresApprovedMatchingDryRunFingerprint() async throws {
        let document = RemovalInputDocument(playlist: "试音", tracks: [target])
        let dryRunClient = RemovalFakeMusicAppClient(playlist: .init(name: "试音", tracks: [target.playlistTrack]))
        let dryRunReport = await RemovalWorkflow(client: dryRunClient).run(
            document: document, options: .init(dryRun: true)
        )
        let fingerprint = try XCTUnwrap(dryRunReport.removalConfirmationFingerprint)

        let noApprovalClient = RemovalFakeMusicAppClient(playlist: .init(name: "试音", tracks: [target.playlistTrack]))
        _ = await RemovalWorkflow(client: noApprovalClient).run(document: document, options: .init())
        let noApprovalWrites = await noApprovalClient.removeCount

        let noFingerprintClient = RemovalFakeMusicAppClient(playlist: .init(name: "试音", tracks: [target.playlistTrack]))
        _ = await RemovalWorkflow(client: noFingerprintClient).run(
            document: document, options: .init(approval: .init(approved: true, confirmationFingerprint: nil))
        )
        let noFingerprintWrites = await noFingerprintClient.removeCount

        let wrongFingerprintClient = RemovalFakeMusicAppClient(playlist: .init(name: "试音", tracks: [target.playlistTrack]))
        _ = await RemovalWorkflow(client: wrongFingerprintClient).run(
            document: document, options: .init(approval: .init(approved: true, confirmationFingerprint: "错误指纹"))
        )
        let wrongFingerprintWrites = await wrongFingerprintClient.removeCount

        let verifiedClient = RemovalFakeMusicAppClient(
            playlist: .init(name: "试音", tracks: [target.playlistTrack]),
            verificationSnapshots: [.init(name: "试音", tracks: [])]
        )
        let verifiedReport = await RemovalWorkflow(client: verifiedClient).run(
            document: document,
            options: .init(approval: .init(approved: true, confirmationFingerprint: fingerprint))
        )
        let verifiedWrites = await verifiedClient.removeCount

        XCTAssertEqual(noApprovalWrites, 0)
        XCTAssertEqual(noFingerprintWrites, 0)
        XCTAssertEqual(wrongFingerprintWrites, 0)
        XCTAssertEqual(verifiedReport.results.map(\.status), [.removed])
        XCTAssertEqual(verifiedWrites, 1)
    }

    func testVerificationReadFailureRequiresRecoveryBeforeLaterWrite() async throws {
        let document = RemovalInputDocument(playlist: "试音", tracks: [target, other])
        let initial = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack, other.playlistTrack])
        let recovered = PlaylistSnapshot(name: "试音", tracks: [other.playlistTrack])
        let afterSecondRemoval = PlaylistSnapshot(name: "试音", tracks: [])
        let dryRunClient = RemovalFakeMusicAppClient(playlist: initial)
        let dryRunReport = await RemovalWorkflow(client: dryRunClient).run(document: document, options: .init(dryRun: true))
        let fingerprint = try XCTUnwrap(dryRunReport.removalConfirmationFingerprint)
        let client = RemovalFakeMusicAppClient(
            playlist: initial,
            playlistOutcomes: [.snapshot(initial), .failure, .snapshot(recovered), .snapshot(afterSecondRemoval)]
        )

        let report = await RemovalWorkflow(client: client).run(
            document: document,
            options: .init(approval: .init(approved: true, confirmationFingerprint: fingerprint))
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
        let approval = try await approval(for: document, snapshot: before)

        let report = await RemovalWorkflow(client: client).run(
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
        let approval = try await approval(for: document, snapshot: snapshot)

        let report = await RemovalWorkflow(client: client).run(
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
        let approval = try await approval(for: document, snapshot: before)

        let report = await RemovalWorkflow(client: client).run(
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
        let approval = try await approval(for: document, snapshot: before)

        let report = await RemovalWorkflow(client: client).run(
            document: document, options: .init(approval: approval)
        )

        XCTAssertEqual(report.results.map(\.status), [.failed, .removed])
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 2)
    }

    private func approval(for document: RemovalInputDocument, snapshot: PlaylistSnapshot) async throws -> RemovalApproval {
        let client = RemovalFakeMusicAppClient(playlist: snapshot)
        let report = await RemovalWorkflow(client: client).run(document: document, options: .init(dryRun: true))
        return .init(approved: true, confirmationFingerprint: try XCTUnwrap(report.removalConfirmationFingerprint))
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
