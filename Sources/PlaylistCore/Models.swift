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
