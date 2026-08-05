import Foundation

public struct PlaylistTrack: Codable, Equatable, Sendable {
    public let name: String
    public let artist: String
    public let databaseID: String?

    public init(name: String, artist: String, databaseID: String? = nil) {
        self.name = name
        self.artist = artist
        self.databaseID = databaseID
    }

    public var key: TrackKey { TrackKey(name: name, artist: artist) }
}

public struct PlaylistSnapshot: Codable, Equatable, Sendable {
    public let name: String
    public let tracks: [PlaylistTrack]

    public init(name: String, tracks: [PlaylistTrack]) {
        self.name = name
        self.tracks = tracks
    }
}

public enum AddTrackOutcome: Equatable, Sendable {
    case submitted
    case notFound
}

public protocol MusicAppClient: Sendable {
    func accessibilityAuthorized() async -> Bool
    func playlist(named: String) async throws -> PlaylistSnapshot?
    func createPlaylist(named: String) async throws
    func add(_ track: CatalogTrack, to playlist: String, timeout: Duration) async throws -> AddTrackOutcome
    func play(track: CatalogTrack, in playlist: String) async throws
}

public struct WorkflowOptions: Sendable, Equatable {
    public let playlistName: String?
    public let create: Bool
    public let dryRun: Bool
    public let playFirst: Bool
    public let timeout: Duration

    public init(
        playlistName: String? = nil,
        create: Bool = false,
        dryRun: Bool = false,
        playFirst: Bool = false,
        timeout: Duration = .seconds(20)
    ) {
        self.playlistName = playlistName
        self.create = create
        self.dryRun = dryRun
        self.playFirst = playFirst
        self.timeout = timeout
    }
}
