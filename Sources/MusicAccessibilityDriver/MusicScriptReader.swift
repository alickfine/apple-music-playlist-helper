import Foundation
import PlaylistCore

public enum MusicScriptError: LocalizedError, Equatable, Sendable {
    case executionFailed(exitCode: Int32, diagnostic: String)
    case invalidOutput(String)
    case ambiguousTrack

    public var errorDescription: String? {
        switch self {
        case let .executionFailed(exitCode, diagnostic):
            "音乐脚本执行失败（退出码 \(exitCode)）：\(diagnostic)"
        case let .invalidOutput(detail):
            "音乐脚本输出解析失败：\(detail)"
        case .ambiguousTrack:
            "目标播放列表中没有唯一匹配的曲目，未执行播放。"
        }
    }
}

public struct MusicScriptReader: Sendable {
    private let runner: any ProcessRunning
    private let osascript = URL(fileURLWithPath: "/usr/bin/osascript")

    public init(runner: any ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    public func playlist(named name: String) async throws -> PlaylistSnapshot? {
        let quotedName = try javaScriptLiteral(name)
        let script = """
        const app = Application('Music');
        const wanted = \(quotedName);
        const lists = app.userPlaylists().filter(p => p.name() === wanted);
        let output;
        if (lists.length === 0) {
          output = 'null';
        } else {
          const p = lists[0];
          const tracks = p.tracks().map(t => ({name: t.name(), artist: t.artist(), databaseId: String(t.databaseID())}));
          output = JSON.stringify({name: p.name(), tracks: tracks});
        }
        output;
        """
        let output = try await execute(script)
        if String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
            return nil
        }
        do {
            return try JSONDecoder().decode(PlaylistSnapshot.self, from: output)
        } catch {
            throw MusicScriptError.invalidOutput(error.localizedDescription)
        }
    }

    public func createPlaylist(named name: String) async throws {
        let quotedName = try javaScriptLiteral(name)
        let script = """
        const app = Application('Music');
        app.make({new: 'userPlaylist', withProperties: {name: \(quotedName)}});
        """
        _ = try await execute(script)
    }

    public func remove(_ track: RemovalTrack, from playlistName: String) async throws {
        let quotedPlaylist = try javaScriptLiteral(playlistName)
        let quotedDatabaseID = try javaScriptLiteral(track.databaseID)
        let quotedName = try javaScriptLiteral(track.name)
        let quotedArtist = try javaScriptLiteral(track.artist)
        let script = """
        const app = Application('Music');
        const lists = app.userPlaylists().filter(p => p.name() === \(quotedPlaylist));
        if (lists.length !== 1) throw new Error('目标播放列表不唯一');
        const playlist = lists[0];
        const matches = playlist.tracks().filter(t =>
          String(t.databaseID()) === \(quotedDatabaseID) &&
          t.name() === \(quotedName) &&
          t.artist() === \(quotedArtist)
        );
        if (matches.length !== 1) throw new Error('曲目不再唯一');
        app.delete(matches[0]);
        """
        _ = try await execute(script)
    }

    public func play(track: CatalogTrack, in playlistName: String) async throws {
        guard let snapshot = try await playlist(named: playlistName) else {
            throw MusicScriptError.ambiguousTrack
        }
        let key = TrackKey(name: track.name, artist: track.artist)
        let matches = snapshot.tracks.filter { $0.key == key }
        guard matches.count == 1, let match = matches.first else {
            throw MusicScriptError.ambiguousTrack
        }
        let quotedPlaylist = try javaScriptLiteral(playlistName)
        let quotedName = try javaScriptLiteral(match.name)
        let quotedArtist = try javaScriptLiteral(match.artist)
        let script = """
        const app = Application('Music');
        const p = app.userPlaylists().filter(x => x.name() === \(quotedPlaylist))[0];
        const matches = p.tracks().filter(t => t.name() === \(quotedName) && t.artist() === \(quotedArtist));
        if (matches.length !== 1) throw new Error('曲目不再唯一');
        app.play(matches[0]);
        """
        _ = try await execute(script)
    }

    private func execute(_ script: String) async throws -> Data {
        let result = try await runner.run(
            executable: osascript,
            arguments: ["-l", "JavaScript", "-"],
            stdin: Data(script.utf8)
        )
        guard result.exitCode == 0 else {
            let diagnostic = String(decoding: result.stderr, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MusicScriptError.executionFailed(exitCode: result.exitCode, diagnostic: diagnostic)
        }
        return result.stdout
    }

    private func javaScriptLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
