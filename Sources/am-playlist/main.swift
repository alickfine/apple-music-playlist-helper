import AMPlaylistCLIKit
import Darwin
import Foundation
import MusicAccessibilityDriver
import PlaylistCore

private enum CommandExecutionError: LocalizedError {
    case removeNotImplemented

    var errorDescription: String? {
        switch self {
        case .removeNotImplemented: "remove 命令暂未实现，已安全拒绝执行。"
        }
    }
}

@main
struct AMPlaylistCommand {
    static func main() async {
        do {
            let options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
            guard options.command != .remove else {
                throw CommandExecutionError.removeNotImplemented
            }
            let data = try Data(contentsOf: options.input)
            let source = try JSONDecoder().decode(TrackInputDocument.self, from: data)
            let playlist = try options.resolvedPlaylist(documentPlaylist: source.playlist)
            let document = TrackInputDocument(playlist: playlist, tracks: source.tracks)
            let workflowOptions = WorkflowOptions(
                playlistName: playlist,
                create: options.create,
                dryRun: options.dryRun,
                playFirst: options.playFirst,
                timeout: .seconds(options.timeoutSeconds)
            )
            let report = await PlaylistWorkflow(client: MusicAccessibilityDriver()).run(
                document: document, options: workflowOptions
            )
            let output = try ResultRenderer.render(report: report, json: options.json) + "\n"
            try FileHandle.standardOutput.write(contentsOf: Data(output.utf8))
            Darwin.exit(exitCode(for: report))
        } catch {
            let message = "错误：\(error.localizedDescription)\n"
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            Darwin.exit(2)
        }
    }

    private static func exitCode(for report: WorkflowReport) -> Int32 {
        if report.results.contains(where: { $0.status == .permissionDenied }) { return 3 }
        if report.results.contains(where: { $0.status == .playlistMissing }) { return 4 }
        return report.exitCode
    }
}
