import AMPlaylistCLIKit
import Darwin
import Foundation
import MusicAccessibilityDriver
import PlaylistCore

private enum CommandExecutionError: LocalizedError {
    case inputReadFailed
    case invalidInput
    case missingReceiptDirectory

    var errorDescription: String? {
        switch self {
        case .inputReadFailed: "无法读取输入文件。"
        case .invalidInput: "输入 JSON 格式无效或字段不符合要求。"
        case .missingReceiptDirectory: "remove 命令缺少有效的临时收据目录。"
        }
    }
}

@main
struct AMPlaylistCommand {
    static func main() async {
        do {
            let options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
            let data: Data
            do {
                data = try Data(contentsOf: options.input)
            } catch {
                throw CommandExecutionError.inputReadFailed
            }
            let report = try await run(options: options, data: data)
            let output = try ResultRenderer.render(report: report, json: options.json) + "\n"
            try FileHandle.standardOutput.write(contentsOf: Data(output.utf8))
            Darwin.exit(exitCode(for: report))
        } catch {
            let message = "错误：\(error.localizedDescription)\n"
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            Darwin.exit(2)
        }
    }

    private static func run(options: CLIOptions, data: Data) async throws -> WorkflowReport {
        let decoder = JSONDecoder()
        switch options.command {
        case .add:
            let source: TrackInputDocument
            do {
                source = try decoder.decode(TrackInputDocument.self, from: data)
            } catch {
                throw CommandExecutionError.invalidInput
            }
            let playlist = try options.resolvedPlaylist(documentPlaylist: source.playlist)
            let document = TrackInputDocument(playlist: playlist, tracks: source.tracks)
            let workflowOptions = WorkflowOptions(
                playlistName: playlist,
                create: options.create,
                dryRun: options.dryRun,
                playFirst: options.playFirst,
                timeout: .seconds(options.timeoutSeconds)
            )
            return await PlaylistWorkflow(client: MusicAccessibilityDriver()).run(
                document: document, options: workflowOptions
            )
        case .remove:
            let source: RemovalInputDocument
            do {
                source = try decoder.decode(RemovalInputDocument.self, from: data)
            } catch {
                throw CommandExecutionError.invalidInput
            }
            let playlist = try options.resolvedPlaylist(documentPlaylist: source.playlist)
            let document = RemovalInputDocument(playlist: playlist, tracks: source.tracks)
            guard let receiptDirectory = options.receiptDirectory else {
                throw CommandExecutionError.missingReceiptDirectory
            }
            let receiptStore = try FileRemovalReceiptStore(directory: receiptDirectory)
            let approval = options.approved
                ? RemovalApproval(approved: true, receiptToken: options.receiptToken)
                : nil
            return await RemovalWorkflow(
                client: MusicAccessibilityDriver(), receiptStore: receiptStore
            ).run(
                document: document,
                options: .init(playlistName: playlist, dryRun: options.dryRun, approval: approval)
            )
        }
    }

    private static func exitCode(for report: WorkflowReport) -> Int32 {
        if report.results.contains(where: { $0.status == .permissionDenied }) { return 3 }
        if report.results.contains(where: { $0.status == .playlistMissing }) { return 4 }
        return report.exitCode
    }
}
