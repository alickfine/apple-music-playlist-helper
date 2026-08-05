import CryptoKit
import Foundation

public struct RemovalApproval: Sendable, Equatable {
    public let approved: Bool
    public let confirmationFingerprint: String?

    public init(approved: Bool, confirmationFingerprint: String?) {
        self.approved = approved
        self.confirmationFingerprint = confirmationFingerprint
    }
}

public struct RemovalWorkflowOptions: Sendable, Equatable {
    public let playlistName: String?
    public let dryRun: Bool
    public let approval: RemovalApproval?

    public init(playlistName: String? = nil, dryRun: Bool = false, approval: RemovalApproval? = nil) {
        self.playlistName = playlistName
        self.dryRun = dryRun
        self.approval = approval
    }
}

public struct RemovalWorkflow: Sendable {
    private let client: any MusicAppClient

    public init(client: any MusicAppClient) {
        self.client = client
    }

    public func run(document: RemovalInputDocument, options: RemovalWorkflowOptions) async -> WorkflowReport {
        guard await client.accessibilityAuthorized() else {
            return WorkflowReport(results: [
                .init(track: nil, status: .permissionDenied, message: "未获得辅助功能权限，未读取或修改音乐资料库。")
            ])
        }

        let playlistName = options.playlistName ?? document.playlist ?? "试音"
        let confirmationFingerprint = fingerprint(playlistName: playlistName, tracks: document.tracks)
        let initialSnapshot: PlaylistSnapshot
        do {
            guard let playlist = try await client.playlist(named: playlistName) else {
                return missingPlaylistReport(playlistName)
            }
            initialSnapshot = playlist
        } catch {
            return WorkflowReport(results: [
                .init(track: nil, status: .failed, message: "读取播放列表失败：\(error.localizedDescription)")
            ])
        }

        guard options.dryRun || hasValidApproval(options.approval, fingerprint: confirmationFingerprint) else {
            return WorkflowReport(results: document.tracks.map {
                .init(
                    track: nil, removalTrack: $0, status: .failed,
                    message: "未获得与本次清单一致的明确删除批准；请先执行试运行并使用其确认指纹。"
                )
            })
        }

        var snapshot: PlaylistSnapshot? = initialSnapshot
        var results: [TrackOperationResult] = []
        for unvalidatedTrack in document.tracks {
            if snapshot == nil {
                do {
                    guard let recovered = try await client.playlist(named: playlistName) else {
                        results.append(.init(
                            track: nil, removalTrack: unvalidatedTrack, status: .playlistMissing,
                            message: "写后复核未完成且播放列表已不可读取，未执行删除。"
                        ))
                        continue
                    }
                    snapshot = recovered
                } catch {
                    results.append(.init(
                        track: nil, removalTrack: unvalidatedTrack, status: .verificationFailed,
                        message: "写后复核未完成，且无法恢复可信播放列表快照，未执行删除：\(error.localizedDescription)"
                    ))
                    continue
                }
            }

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

            let matches = snapshot!.tracks.filter {
                $0.databaseID == track.databaseID && $0.name == track.name && $0.artist == track.artist
            }
            guard matches.count == 1 else {
                results.append(.init(
                    track: nil, removalTrack: track, status: .notFound,
                    message: matchFailureMessage(count: matches.count)
                ))
                continue
            }

            if options.dryRun {
                results.append(.init(
                    track: nil, removalTrack: track, status: .wouldRemove,
                    message: "试运行：将从播放列表中删除此曲目。"
                ))
                continue
            }

            do {
                try await client.remove(track, from: playlistName)
            } catch {
                results.append(.init(
                    track: nil, removalTrack: track, status: .failed,
                    message: "删除失败：\(error.localizedDescription)"
                ))
                continue
            }

            do {
                guard let verified = try await client.playlist(named: playlistName) else {
                    snapshot = nil
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
                snapshot = nil
                results.append(.init(
                    track: nil, removalTrack: track, status: .verificationFailed,
                    message: "已提交删除操作，但写后复核读取失败：\(error.localizedDescription)"
                ))
            }
        }
        return WorkflowReport(
            results: results,
            removalConfirmationFingerprint: options.dryRun ? confirmationFingerprint : nil
        )
    }

    private func missingPlaylistReport(_ name: String) -> WorkflowReport {
        WorkflowReport(results: [
            .init(track: nil, status: .playlistMissing, message: "播放列表“\(name)”不存在，未执行删除。")
        ])
    }

    private func matchFailureMessage(count: Int) -> String {
        if count == 0 {
            return "目标播放列表中未找到数据库 ID、曲名和艺人均精确匹配的曲目，未执行删除。"
        }
        return "目标播放列表中发现 \(count) 个数据库 ID、曲名和艺人均精确匹配的曲目，匹配不唯一，未执行删除。"
    }

    private func hasValidApproval(_ approval: RemovalApproval?, fingerprint: String) -> Bool {
        approval?.approved == true && approval?.confirmationFingerprint == fingerprint
    }

    private func fingerprint(playlistName: String, tracks: [RemovalTrack]) -> String {
        var data = Data(playlistName.utf8)
        for track in tracks {
            for value in [track.databaseID, track.name, track.artist] {
                let valueData = Data(value.utf8)
                var length = UInt64(valueData.count).bigEndian
                withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
                data.append(valueData)
            }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
