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

        XCTAssertEqual(report.results.map(\.status), [.removed])
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 0)
    }

    func testInputDocumentDecodesThreeExactFieldsUsingDatabaseId() throws {
        let data = Data(#"{"playlist":"试音","tracks":[{"databaseId":"101","name":"被遗忘的时光","artist":"蔡琴"}]}"#.utf8)

        let document = try JSONDecoder().decode(RemovalInputDocument.self, from: data)

        XCTAssertEqual(document, .init(playlist: "试音", tracks: [target]))
    }

    func testOnlyExactDatabaseIDNameAndArtistMatchIsRemoved() async {
        let before = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack])
        let after = PlaylistSnapshot(name: "试音", tracks: [])
        let client = RemovalFakeMusicAppClient(playlist: before, verificationSnapshots: [after])

        let report = await RemovalWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [target]), options: .init()
        )

        XCTAssertEqual(report.results.map(\.status), [.removed])
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 1)
    }

    func testMissingOrAmbiguousMatchDoesNotWrite() async {
        let missing = PlaylistTrack(name: target.name, artist: "其他艺人", databaseID: target.databaseID)
        let ambiguous = PlaylistTrack(name: other.name, artist: other.artist, databaseID: other.databaseID)
        let client = RemovalFakeMusicAppClient(playlist: .init(name: "试音", tracks: [missing, ambiguous, ambiguous]))

        let report = await RemovalWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [target, other]), options: .init()
        )

        XCTAssertEqual(report.results.map(\.status), [.notFound, .notFound])
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 0)
    }

    func testExistingDatabaseIDAfterWriteReturnsVerificationFailure() async {
        let before = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack])
        let client = RemovalFakeMusicAppClient(playlist: before, verificationSnapshots: [before])

        let report = await RemovalWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [target]), options: .init()
        )

        XCTAssertEqual(report.results.map(\.status), [.verificationFailed])
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 1)
    }

    func testFailedItemDoesNotPreventLaterExactRemoval() async {
        let before = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack, other.playlistTrack])
        let afterSecondRemoval = PlaylistSnapshot(name: "试音", tracks: [target.playlistTrack])
        let client = RemovalFakeMusicAppClient(
            playlist: before,
            removeFailures: [true, false],
            verificationSnapshots: [afterSecondRemoval]
        )

        let report = await RemovalWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [target, other]), options: .init()
        )

        XCTAssertEqual(report.results.map(\.status), [.failed, .removed])
        let removeCount = await client.removeCount
        XCTAssertEqual(removeCount, 2)
    }
}

private extension RemovalTrack {
    var playlistTrack: PlaylistTrack {
        PlaylistTrack(name: name, artist: artist, databaseID: databaseID)
    }
}

private enum RemovalFakeError: LocalizedError {
    case removalFailed

    var errorDescription: String? { "模拟删除失败" }
}

private actor RemovalFakeMusicAppClient: MusicAppClient {
    private var initialPlaylist: PlaylistSnapshot?
    private var verificationSnapshots: [PlaylistSnapshot]
    private var removeFailures: [Bool]
    private(set) var removeCount = 0
    private var playlistReadCount = 0

    init(
        playlist: PlaylistSnapshot?,
        removeFailures: [Bool] = [],
        verificationSnapshots: [PlaylistSnapshot] = []
    ) {
        self.initialPlaylist = playlist
        self.removeFailures = removeFailures
        self.verificationSnapshots = verificationSnapshots
    }

    func accessibilityAuthorized() -> Bool { true }

    func playlist(named: String) throws -> PlaylistSnapshot? {
        playlistReadCount += 1
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
