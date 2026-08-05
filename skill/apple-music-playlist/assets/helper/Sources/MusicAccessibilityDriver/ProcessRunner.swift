import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol ProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], stdin: Data?) async throws -> ProcessResult
}

public actor ProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: URL, arguments: [String], stdin: Data?) async throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let standardInput = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.standardInput = standardInput
        try process.run()
        if let stdin {
            try standardInput.fileHandleForWriting.write(contentsOf: stdin)
        }
        try standardInput.fileHandleForWriting.close()
        let stdout = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let stderr = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
