import Foundation
import PlaylistCore

public enum ResultRenderer {
    public static func render(report: WorkflowReport, json: Bool) throws -> String {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return String(decoding: try encoder.encode(report), as: UTF8.self)
        }
        if report.results.isEmpty { return "没有需要处理的曲目。" }
        return report.results.map { result in
            let subject = result.track.map { "\($0.name) — \($0.artist)" }
                ?? result.removalTrack.map { "\($0.name) — \($0.artist)" }
                ?? "播放列表"
            return "[\(label(for: result.status))] \(subject)：\(result.message)"
        }.joined(separator: "\n")
    }

    private static func label(for status: TrackOperationStatus) -> String {
        switch status {
        case .added: "已添加"
        case .removed: "已删除"
        case .skippedDuplicate: "已跳过重复项"
        case .notFound: "未找到"
        case .permissionDenied: "权限不足"
        case .playlistMissing: "播放列表不存在"
        case .verificationFailed: "复核失败"
        case .failed: "失败"
        }
    }
}
