import Foundation

public enum CLICommand: String, Codable, Equatable, Sendable {
    case add
    case remove
}

public enum CLIOptionsError: LocalizedError, Equatable {
    case missingSubcommand
    case unsupportedSubcommand(String)
    case missingValue(String)
    case missingInput
    case invalidTimeout
    case unknownArgument(String)
    case conflictingPlaylistSources
    case unavailableOption(option: String, command: CLICommand)
    case missingReceiptDirectory
    case removalDryRunRequiresJSON
    case removalDryRunCannotBeApproved
    case missingRemovalApproval

    public var errorDescription: String? {
        switch self {
        case .missingSubcommand: "缺少子命令；当前支持 add 和 remove。"
        case let .unsupportedSubcommand(value): "不支持的子命令：\(value)。"
        case let .missingValue(option): "参数 \(option) 缺少取值。"
        case .missingInput: "缺少必需参数 --input。"
        case .invalidTimeout: "--timeout 必须是正整数秒。"
        case .unknownArgument: "存在未知参数。"
        case .conflictingPlaylistSources: "命令行和输入 JSON 同时指定了播放列表，请只保留一处。"
        case let .unavailableOption(option, command): "参数 \(option) 不支持用于 \(command.rawValue) 命令。"
        case .missingReceiptDirectory: "remove 命令必须提供调用者创建的临时收据目录 --receipt-dir。"
        case .removalDryRunRequiresJSON: "删除试运行必须同时提供 --dry-run 和 --json，以便返回一次性收据。"
        case .removalDryRunCannotBeApproved: "删除试运行不得提供 --approved 或 --receipt-token。"
        case .missingRemovalApproval: "实际删除必须同时提供 --approved 和 --receipt-token。"
        }
    }
}

public struct CLIOptions: Equatable, Sendable {
    public let command: CLICommand
    public let playlist: String?
    public let input: URL
    public let create: Bool
    public let dryRun: Bool
    public let playFirst: Bool
    public let timeoutSeconds: Int
    public let json: Bool
    public let receiptDirectory: URL?
    public let approved: Bool
    public let receiptToken: String?

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        guard let commandName = arguments.first else { throw CLIOptionsError.missingSubcommand }
        guard let command = CLICommand(rawValue: commandName) else {
            throw CLIOptionsError.unsupportedSubcommand(commandName)
        }
        var playlist: String?
        var input: URL?
        var create = false
        var dryRun = false
        var playFirst = false
        var timeout = 8
        var json = false
        var receiptDirectory: URL?
        var approved = false
        var receiptToken: String?
        var index = 1

        func value(after option: String) throws -> String {
            guard index + 1 < arguments.count else { throw CLIOptionsError.missingValue(option) }
            return arguments[index + 1]
        }

        while index < arguments.count {
            switch arguments[index] {
            case "--playlist":
                playlist = try value(after: "--playlist"); index += 2
            case "--input":
                input = URL(fileURLWithPath: try value(after: "--input")); index += 2
            case "--timeout":
                guard let parsed = Int(try value(after: "--timeout")), parsed > 0 else {
                    throw CLIOptionsError.invalidTimeout
                }
                timeout = parsed; index += 2
            case "--create":
                guard command == .add else {
                    throw CLIOptionsError.unavailableOption(option: "--create", command: command)
                }
                create = true; index += 1
            case "--dry-run": dryRun = true; index += 1
            case "--play-first":
                guard command == .add else {
                    throw CLIOptionsError.unavailableOption(option: "--play-first", command: command)
                }
                playFirst = true; index += 1
            case "--json": json = true; index += 1
            case "--receipt-dir":
                guard command == .remove else {
                    throw CLIOptionsError.unavailableOption(option: "--receipt-dir", command: command)
                }
                receiptDirectory = URL(fileURLWithPath: try value(after: "--receipt-dir")); index += 2
            case "--approved":
                guard command == .remove else {
                    throw CLIOptionsError.unavailableOption(option: "--approved", command: command)
                }
                approved = true; index += 1
            case "--receipt-token":
                guard command == .remove else {
                    throw CLIOptionsError.unavailableOption(option: "--receipt-token", command: command)
                }
                receiptToken = try value(after: "--receipt-token"); index += 2
            default: throw CLIOptionsError.unknownArgument(arguments[index])
            }
        }
        guard let input else { throw CLIOptionsError.missingInput }
        if command == .remove {
            guard receiptDirectory != nil else { throw CLIOptionsError.missingReceiptDirectory }
            if dryRun {
                guard json else { throw CLIOptionsError.removalDryRunRequiresJSON }
                guard !approved, receiptToken == nil else { throw CLIOptionsError.removalDryRunCannotBeApproved }
            } else {
                guard approved, receiptToken != nil else { throw CLIOptionsError.missingRemovalApproval }
            }
        }
        return CLIOptions(
            command: command, playlist: playlist, input: input, create: create, dryRun: dryRun,
            playFirst: playFirst, timeoutSeconds: timeout, json: json,
            receiptDirectory: receiptDirectory, approved: approved, receiptToken: receiptToken
        )
    }

    public func resolvedPlaylist(documentPlaylist: String?) throws -> String {
        if playlist != nil, documentPlaylist != nil { throw CLIOptionsError.conflictingPlaylistSources }
        return playlist ?? documentPlaylist ?? "试音"
    }
}
