import CryptoKit
import Foundation

public struct RemovalApproval: Sendable, Equatable {
    public let approved: Bool
    public let receiptToken: String?

    public init(approved: Bool, receiptToken: String?) {
        self.approved = approved
        self.receiptToken = receiptToken
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
    private let receiptStore: any RemovalReceiptStore

    public init(client: any MusicAppClient, receiptStore: any RemovalReceiptStore) {
        self.client = client
        self.receiptStore = receiptStore
    }

    public func run(document: RemovalInputDocument, options: RemovalWorkflowOptions) async -> WorkflowReport {
        guard await client.accessibilityAuthorized() else {
            return WorkflowReport(results: [
                .init(track: nil, status: .permissionDenied, message: "未获得辅助功能权限，未读取或修改音乐资料库。")
            ])
        }

        let playlistName = options.playlistName ?? document.playlist ?? "试音"
        let snapshot: PlaylistSnapshot
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

        let artifact = receiptArtifact(playlistName: playlistName, document: document, snapshot: snapshot)
        if options.dryRun {
            let token = await receiptStore.issue(artifact)
            return WorkflowReport(
                results: dryRunResults(for: artifact.matchResults),
                removalReceiptToken: token
            )
        }

        guard let approval = options.approval, approval.approved, let token = approval.receiptToken,
              let storedArtifact = await receiptStore.receipt(for: token) else {
            return rejectedApprovalReport(document.tracks)
        }
        guard storedArtifact == artifact else {
            return WorkflowReport(results: document.tracks.map {
                .init(
                    track: nil, removalTrack: $0, status: .failed,
                    message: "删除收据与当前播放列表快照或清单不一致；未执行删除，请重新试运行。"
                )
            })
        }
        guard await receiptStore.consume(token: token, matching: artifact) else {
            return rejectedApprovalReport(document.tracks)
        }

        return await executeApprovedRemoval(document: document, playlistName: playlistName, initialSnapshot: snapshot)
    }

    private func executeApprovedRemoval(
        document: RemovalInputDocument,
        playlistName: String,
        initialSnapshot: PlaylistSnapshot
    ) async -> WorkflowReport {
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
                results.append(.init(track: nil, removalTrack: unvalidatedTrack, status: .failed, message: error.localizedDescription))
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

            do {
                try await client.remove(track, from: playlistName)
            } catch {
                results.append(.init(track: nil, removalTrack: track, status: .failed, message: "删除失败：\(error.localizedDescription)"))
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
                results.append(.init(track: nil, removalTrack: track, status: .removed, message: "已从播放列表删除并通过写后复核。"))
            } catch {
                snapshot = nil
                results.append(.init(
                    track: nil, removalTrack: track, status: .verificationFailed,
                    message: "已提交删除操作，但写后复核读取失败：\(error.localizedDescription)"
                ))
            }
        }
        return WorkflowReport(results: results)
    }

    private func receiptArtifact(
        playlistName: String,
        document: RemovalInputDocument,
        snapshot: PlaylistSnapshot
    ) -> RemovalReceiptArtifact {
        let matchResults = document.tracks.map { track in
            guard (try? track.validated()) != nil else {
                return RemovalReceiptMatch(track: track, exactMatchCount: -1)
            }
            let count = snapshot.tracks.filter {
                $0.databaseID == track.databaseID && $0.name == track.name && $0.artist == track.artist
            }.count
            return RemovalReceiptMatch(track: track, exactMatchCount: count)
        }
        return RemovalReceiptArtifact(
            playlistName: playlistName,
            tracks: document.tracks,
            playlistSnapshotFingerprint: snapshotFingerprint(snapshot),
            matchResults: matchResults,
            wouldRemoveTracks: matchResults.filter { $0.exactMatchCount == 1 }.map(\.track)
        )
    }

    private func dryRunResults(for matchResults: [RemovalReceiptMatch]) -> [TrackOperationResult] {
        matchResults.map { match in
            switch match.exactMatchCount {
            case 1:
                .init(track: nil, removalTrack: match.track, status: .wouldRemove, message: "试运行：将从播放列表中删除此曲目。")
            case 0:
                .init(track: nil, removalTrack: match.track, status: .notFound, message: matchFailureMessage(count: 0))
            case let count where count > 1:
                .init(track: nil, removalTrack: match.track, status: .notFound, message: matchFailureMessage(count: count))
            default:
                .init(track: nil, removalTrack: match.track, status: .failed, message: invalidTrackMessage(match.track))
            }
        }
    }

    private func rejectedApprovalReport(_ tracks: [RemovalTrack]) -> WorkflowReport {
        WorkflowReport(results: tracks.map {
            .init(
                track: nil, removalTrack: $0, status: .failed,
                message: "未获得尚未消费且与本次清单一致的删除收据；请先执行试运行。"
            )
        })
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

    private func invalidTrackMessage(_ track: RemovalTrack) -> String {
        do {
            _ = try track.validated()
            return "删除项无效。"
        } catch {
            return error.localizedDescription
        }
    }

    private func snapshotFingerprint(_ snapshot: PlaylistSnapshot) -> String {
        var data = Data()
        append(snapshot.name, to: &data)
        var count = UInt64(snapshot.tracks.count).bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        for track in snapshot.tracks {
            append(track.name, to: &data)
            append(track.artist, to: &data)
            append(track.databaseID ?? "", to: &data)
            data.append(track.databaseID == nil ? 0 : 1)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func append(_ value: String, to data: inout Data) {
        let valueData = Data(value.utf8)
        var length = UInt64(valueData.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(valueData)
    }
}
