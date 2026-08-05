import Foundation

public struct RemovalWorkflow: Sendable {
    private let client: any MusicAppClient

    public init(client: any MusicAppClient) {
        self.client = client
    }

    public func run(document: RemovalInputDocument, options: WorkflowOptions) async -> WorkflowReport {
        guard await client.accessibilityAuthorized() else {
            return WorkflowReport(results: [
                .init(track: nil, status: .permissionDenied, message: "未获得辅助功能权限，未读取或修改音乐资料库。")
            ])
        }

        let playlistName = options.playlistName ?? document.playlist ?? "试音"
        var snapshot: PlaylistSnapshot
        do {
            guard let playlist = try await client.playlist(named: playlistName) else {
                return missingPlaylistReport(playlistName)
            }
            snapshot = playlist
        } catch {
            return WorkflowReport(results: [
                .init(track: nil, status: .failed, message: "读取播放列表失败：\(error.localizedDescription)")
            ])
        }

        var results: [TrackOperationResult] = []
        for unvalidatedTrack in document.tracks {
            let track: RemovalTrack
            do {
                track = try unvalidatedTrack.validated()
            } catch {
                results.append(.init(
                    track: nil, removalTrack: unvalidatedTrack, status: .failed,
                    message: error.localizedDescription
                ))
                continue
            }

            let matches = snapshot.tracks.filter {
                $0.databaseID == track.databaseID && $0.name == track.name && $0.artist == track.artist
            }
            guard matches.count == 1 else {
                results.append(.init(
                    track: nil, removalTrack: track, status: .notFound,
                    message: matchFailureMessage(for: track, count: matches.count)
                ))
                continue
            }

            if options.dryRun {
                results.append(.init(
                    track: nil, removalTrack: track, status: .removed,
                    message: "试运行：将从播放列表中删除此曲目。"
                ))
                continue
            }

            do {
                try await client.remove(track, from: playlistName)
                guard let verified = try await client.playlist(named: playlistName) else {
                    results.append(.init(
                        track: nil, removalTrack: track, status: .verificationFailed,
                        message: "已提交删除操作，但写后复核无法读取播放列表。"
                    ))
                    continue
                }
                snapshot = verified
                guard !verified.tracks.contains(where: { $0.databaseID == track.databaseID }) else {
                    results.append(.init(
                        track: nil, removalTrack: track, status: .verificationFailed,
                        message: "已提交删除操作，但写后复核仍发现该数据库 ID。"
                    ))
                    continue
                }
                results.append(.init(
                    track: nil, removalTrack: track, status: .removed,
                    message: "已从播放列表删除并通过写后复核。"
                ))
            } catch {
                results.append(.init(
                    track: nil, removalTrack: track, status: .failed,
                    message: "删除失败：\(error.localizedDescription)"
                ))
            }
        }
        return WorkflowReport(results: results)
    }

    private func missingPlaylistReport(_ name: String) -> WorkflowReport {
        WorkflowReport(results: [
            .init(track: nil, status: .playlistMissing, message: "播放列表“\(name)”不存在，未执行删除。")
        ])
    }

    private func matchFailureMessage(for track: RemovalTrack, count: Int) -> String {
        if count == 0 {
            return "目标播放列表中未找到数据库 ID、曲名和艺人均精确匹配的曲目，未执行删除。"
        }
        return "目标播放列表中发现 \(count) 个数据库 ID、曲名和艺人均精确匹配的曲目，匹配不唯一，未执行删除。"
    }
}
