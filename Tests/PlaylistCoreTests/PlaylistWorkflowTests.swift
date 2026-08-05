import XCTest
@testable import PlaylistCore

final class PlaylistWorkflowTests: XCTestCase {
    private let first = CatalogTrack(
        id: "905228611", name: "被遗忘的时光", artist: "蔡琴",
        url: URL(string: "https://music.apple.com/cn/album/example/905228600?i=905228611")!
    )
    private let second = CatalogTrack(
        id: "1440780951", name: "Hotel California", artist: "Eagles",
        url: URL(string: "https://music.apple.com/cn/album/example/1440780949?i=1440780951")!
    )

    func testNoAccessibilityPermissionDoesNotReadPlaylist() async {
        let client = FakeMusicAppClient(authorized: false)
        let report = await PlaylistWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [first]), options: .init()
        )
        XCTAssertEqual(report.results.map(\.status), [.permissionDenied])
        let playlistReadCount = await client.playlistReadCount
        XCTAssertEqual(playlistReadCount, 0)
    }

    func testMissingPlaylistDoesNotCreateWithoutFlag() async {
        let client = FakeMusicAppClient(playlist: nil)
        let report = await PlaylistWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [first]), options: .init()
        )
        XCTAssertEqual(report.results.map(\.status), [.playlistMissing])
        let createCount = await client.createCount
        XCTAssertEqual(createCount, 0)
    }

    func testCreateFlagCreatesPlaylistOnce() async {
        let client = FakeMusicAppClient(playlist: nil, snapshotsAfterCreate: [.init(name: "试音", tracks: [])])
        _ = await PlaylistWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: []), options: .init(create: true)
        )
        let createCount = await client.createCount
        XCTAssertEqual(createCount, 1)
    }

    func testDryRunSkipsExistingAndPerformsNoWrites() async {
        let existing = PlaylistSnapshot(name: "试音", tracks: [.init(name: first.name, artist: first.artist)])
        let client = FakeMusicAppClient(playlist: existing)
        let report = await PlaylistWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [first, second]), options: .init(dryRun: true)
        )
        XCTAssertEqual(report.results.map(\.status), [.skippedDuplicate, .added])
        let addCount = await client.addCount
        let playCount = await client.playCount
        XCTAssertEqual(addCount, 0)
        XCTAssertEqual(playCount, 0)
    }

    func testDuplicateIsSkippedAndSuccessfulAddIsVerified() async {
        let existing = PlaylistSnapshot(name: "试音", tracks: [.init(name: first.name, artist: first.artist)])
        let verified = PlaylistSnapshot(name: "试音", tracks: [
            .init(name: first.name, artist: first.artist), .init(name: second.name, artist: second.artist)
        ])
        let client = FakeMusicAppClient(playlist: existing, verificationSnapshots: [verified])
        let report = await PlaylistWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [first, second]), options: .init()
        )
        XCTAssertEqual(report.results.map(\.status), [.skippedDuplicate, .added])
        let addCount = await client.addCount
        let playlistReadCount = await client.playlistReadCount
        XCTAssertEqual(addCount, 1)
        XCTAssertEqual(playlistReadCount, 2)
    }

    func testFailureContinuesAndMissingVerificationIsReported() async {
        let empty = PlaylistSnapshot(name: "试音", tracks: [])
        let client = FakeMusicAppClient(
            playlist: empty,
            addOutcomes: [.notFound, .submitted],
            verificationSnapshots: [empty]
        )
        let report = await PlaylistWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [first, second]), options: .init()
        )
        XCTAssertEqual(report.results.map(\.status), [.notFound, .verificationFailed])
        let addCount = await client.addCount
        XCTAssertEqual(addCount, 2)
    }

    func testPlayFirstPlaysOnlyFirstAddedTrack() async {
        let empty = PlaylistSnapshot(name: "试音", tracks: [])
        let firstOnly = PlaylistSnapshot(name: "试音", tracks: [.init(name: first.name, artist: first.artist)])
        let both = PlaylistSnapshot(name: "试音", tracks: [
            .init(name: first.name, artist: first.artist), .init(name: second.name, artist: second.artist)
        ])
        let client = FakeMusicAppClient(
            playlist: empty, addOutcomes: [.submitted, .submitted], verificationSnapshots: [firstOnly, both]
        )
        _ = await PlaylistWorkflow(client: client).run(
            document: .init(playlist: "试音", tracks: [first, second]), options: .init(playFirst: true)
        )
        let playCount = await client.playCount
        let playedTrackID = await client.playedTrackID
        XCTAssertEqual(playCount, 1)
        XCTAssertEqual(playedTrackID, first.id)
    }
}

private actor FakeMusicAppClient: MusicAppClient {
    let authorized: Bool
    var initialPlaylist: PlaylistSnapshot?
    var snapshotsAfterCreate: [PlaylistSnapshot]
    var addOutcomes: [AddTrackOutcome]
    var verificationSnapshots: [PlaylistSnapshot]
    private(set) var playlistReadCount = 0
    private(set) var createCount = 0
    private(set) var addCount = 0
    private(set) var playCount = 0
    private(set) var playedTrackID: String?

    init(
        authorized: Bool = true,
        playlist: PlaylistSnapshot? = .init(name: "试音", tracks: []),
        snapshotsAfterCreate: [PlaylistSnapshot] = [],
        addOutcomes: [AddTrackOutcome] = [],
        verificationSnapshots: [PlaylistSnapshot] = []
    ) {
        self.authorized = authorized
        self.initialPlaylist = playlist
        self.snapshotsAfterCreate = snapshotsAfterCreate
        self.addOutcomes = addOutcomes
        self.verificationSnapshots = verificationSnapshots
    }

    func accessibilityAuthorized() -> Bool { authorized }

    func playlist(named: String) throws -> PlaylistSnapshot? {
        playlistReadCount += 1
        if playlistReadCount == 1 { return initialPlaylist }
        if !snapshotsAfterCreate.isEmpty { return snapshotsAfterCreate.removeFirst() }
        if !verificationSnapshots.isEmpty { return verificationSnapshots.removeFirst() }
        return initialPlaylist
    }

    func createPlaylist(named: String) { createCount += 1 }

    func add(_ track: CatalogTrack, to playlist: String, timeout: Duration) throws -> AddTrackOutcome {
        addCount += 1
        return addOutcomes.isEmpty ? .submitted : addOutcomes.removeFirst()
    }

    func remove(_ track: RemovalTrack, from playlist: String) {}

    func play(track: CatalogTrack, in playlist: String) { playCount += 1; playedTrackID = track.id }
}
