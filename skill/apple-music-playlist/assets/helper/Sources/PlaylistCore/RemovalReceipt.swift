import Foundation

public struct RemovalReceiptMatch: Codable, Sendable, Equatable {
    public let track: RemovalTrack
    public let exactMatchCount: Int

    public init(track: RemovalTrack, exactMatchCount: Int) {
        self.track = track
        self.exactMatchCount = exactMatchCount
    }
}

public struct RemovalReceiptArtifact: Codable, Sendable, Equatable {
    public let playlistName: String
    public let tracks: [RemovalTrack]
    public let playlistSnapshotFingerprint: String
    public let matchResults: [RemovalReceiptMatch]
    public let wouldRemoveTracks: [RemovalTrack]

    public init(
        playlistName: String,
        tracks: [RemovalTrack],
        playlistSnapshotFingerprint: String,
        matchResults: [RemovalReceiptMatch],
        wouldRemoveTracks: [RemovalTrack]
    ) {
        self.playlistName = playlistName
        self.tracks = tracks
        self.playlistSnapshotFingerprint = playlistSnapshotFingerprint
        self.matchResults = matchResults
        self.wouldRemoveTracks = wouldRemoveTracks
    }
}

public protocol RemovalReceiptStore: Sendable {
    func issue(_ artifact: RemovalReceiptArtifact) async -> String
    func receipt(for token: String) async -> RemovalReceiptArtifact?
    func consume(token: String, matching artifact: RemovalReceiptArtifact) async -> Bool
}
