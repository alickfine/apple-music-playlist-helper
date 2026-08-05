import Foundation

public struct PlaylistWorkflow: Sendable {
    private let client: any MusicAppClient

    public init(client: any MusicAppClient) {
        self.client = client
    }

    public func run(document: TrackInputDocument, options: WorkflowOptions) async -> WorkflowReport {
        guard await client.accessibilityAuthorized() else {
            return WorkflowReport(results: [
                .init(track: nil, status: .permissionDenied, message: "未获得辅助功能权限，未读取或修改音乐资料库。")
            ])
        }

        let playlistName = options.playlistName ?? document.playlist ?? "试音"
        var snapshot: PlaylistSnapshot
        do {
            if let existing = try await client.playlist(named: playlistName) {
                snapshot = existing
            } else if options.create {
                if options.dryRun {
                    snapshot = PlaylistSnapshot(name: playlistName, tracks: [])
                } else {
                    try await client.createPlaylist(named: playlistName)
                    guard let created = try await client.playlist(named: playlistName) else {
                        return missingPlaylistReport(playlistName)
                    }
                    snapshot = created
                }
            } else {
                return missingPlaylistReport(playlistName)
            }
        } catch {
            return WorkflowReport(results: [
                .init(track: nil, status: .failed, message: "读取播放列表失败：\(error.localizedDescription)")
            ])
        }

        var knownKeys = Set(snapshot.tracks.map(\.key))
        var results: [TrackOperationResult] = []
        var firstAdded: CatalogTrack?

        for unvalidatedTrack in document.tracks {
            let track: CatalogTrack
            do {
                track = try unvalidatedTrack.validated()
            } catch {
                results.append(.init(track: unvalidatedTrack, status: .failed, message: error.localizedDescription))
                continue
            }

            let key = TrackKey(name: track.name, artist: track.artist)
            guard !knownKeys.contains(key) else {
                results.append(.init(track: track, status: .skippedDuplicate, message: "播放列表中已存在，已跳过。"))
                continue
            }

            if options.dryRun {
                knownKeys.insert(key)
                results.append(.init(track: track, status: .added, message: "试运行：将添加此曲目。"))
                continue
            }

            do {
                switch try await client.add(track, to: playlistName, timeout: options.timeout) {
                case .notFound:
                    results.append(.init(track: track, status: .notFound, message: "未找到与目录 ID 准确匹配的曲目。"))
                case .submitted:
                    guard let verified = try await client.playlist(named: playlistName),
                          verified.tracks.map(\.key).contains(key) else {
                        results.append(.init(track: track, status: .verificationFailed, message: "已提交添加操作，但写后复核未找到曲目。"))
                        continue
                    }
                    snapshot = verified
                    knownKeys = Set(snapshot.tracks.map(\.key))
                    firstAdded = firstAdded ?? track
                    results.append(.init(track: track, status: .added, message: "已添加并通过写后复核。"))
                }
            } catch {
                results.append(.init(track: track, status: .failed, message: "添加失败：\(error.localizedDescription)"))
            }
        }

        if options.playFirst, let firstAdded, !options.dryRun {
            do {
                try await client.play(track: firstAdded, in: playlistName)
            } catch {
                results.append(.init(track: firstAdded, status: .failed, message: "播放首个新增曲目失败：\(error.localizedDescription)"))
            }
        }
        return WorkflowReport(results: results)
    }

    private func missingPlaylistReport(_ name: String) -> WorkflowReport {
        WorkflowReport(results: [
            .init(track: nil, status: .playlistMissing, message: "播放列表“\(name)”不存在；如需创建，请明确传入 --create。")
        ])
    }
}
