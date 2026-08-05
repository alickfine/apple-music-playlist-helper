import Foundation

public struct CatalogTrack: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let artist: String
    public let url: URL

    public init(id: String, name: String, artist: String, url: URL) {
        self.id = id
        self.name = name
        self.artist = artist
        self.url = url
    }
}

public struct TrackInputDocument: Codable, Equatable, Sendable {
    public let playlist: String?
    public let tracks: [CatalogTrack]

    public init(playlist: String? = nil, tracks: [CatalogTrack]) {
        self.playlist = playlist
        self.tracks = tracks
    }
}

public struct RemovalTrack: Codable, Equatable, Sendable {
    public let databaseID: String

    public init(databaseID: String) {
        self.databaseID = databaseID
    }
}

public struct RemovalInputDocument: Codable, Equatable, Sendable {
    public let playlist: String?
    public let tracks: [RemovalTrack]

    public init(playlist: String? = nil, tracks: [RemovalTrack]) {
        self.playlist = playlist
        self.tracks = tracks
    }
}

public struct TrackKey: Hashable, Codable, Sendable {
    public let name: String
    public let artist: String

    public init(name: String, artist: String) {
        self.name = TextNormalization.normalize(name)
        self.artist = TextNormalization.normalize(artist)
    }
}

public enum TrackOperationStatus: String, Codable, Equatable, Sendable {
    case added
    case skippedDuplicate = "skipped_duplicate"
    case notFound = "not_found"
    case permissionDenied = "permission_denied"
    case playlistMissing = "playlist_missing"
    case verificationFailed = "verification_failed"
    case failed
}

public struct TrackOperationResult: Codable, Equatable, Sendable {
    public let track: CatalogTrack?
    public let status: TrackOperationStatus
    public let message: String

    public init(track: CatalogTrack?, status: TrackOperationStatus, message: String) {
        self.track = track
        self.status = status
        self.message = message
    }
}

public struct WorkflowReport: Codable, Equatable, Sendable {
    public let results: [TrackOperationResult]

    public init(results: [TrackOperationResult]) {
        self.results = results
    }

    public var exitCode: Int32 {
        let successful: Set<TrackOperationStatus> = [.added, .skippedDuplicate]
        return results.allSatisfy { successful.contains($0.status) } ? 0 : 5
    }
}

public enum TrackValidationError: Error, Equatable, Sendable {
    case invalidCatalogID
    case emptyName
    case emptyArtist
    case invalidScheme
    case invalidHost
    case missingCatalogID
    case ambiguousCatalogID
    case catalogIDMismatch
}

extension TrackValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCatalogID:
            "目录 ID 必须只包含 ASCII 数字。"
        case .emptyName:
            "曲名不能为空。"
        case .emptyArtist:
            "艺人不能为空。"
        case .invalidScheme:
            "曲目 URL 必须使用 HTTPS。"
        case .invalidHost:
            "曲目 URL 主机必须是 music.apple.com。"
        case .missingCatalogID:
            "曲目 URL 缺少 i 查询参数。"
        case .ambiguousCatalogID:
            "曲目 URL 只能包含一个 i 查询参数。"
        case .catalogIDMismatch:
            "曲目 URL 中的目录 ID 与 id 字段不一致。"
        }
    }
}
