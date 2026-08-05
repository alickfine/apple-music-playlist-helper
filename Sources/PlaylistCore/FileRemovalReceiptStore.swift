import Darwin
import Foundation
import Security

public enum FileRemovalReceiptStoreError: LocalizedError, Equatable, Sendable {
    case invalidDirectory

    public var errorDescription: String? {
        switch self {
        case .invalidDirectory:
            "收据目录必须由调用者预先创建，且必须是可访问的目录。"
        }
    }
}

public actor FileRemovalReceiptStore: RemovalReceiptStore {
    private let directory: URL

    public init(directory: URL) throws {
        let normalized = directory.standardizedFileURL
        let values = try? normalized.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else {
            throw FileRemovalReceiptStoreError.invalidDirectory
        }
        self.directory = normalized
    }

    public func issue(_ artifact: RemovalReceiptArtifact) -> String {
        guard let data = try? JSONEncoder().encode(artifact) else { return "" }
        for _ in 0..<4 {
            guard let token = Self.randomToken() else { return "" }
            let destination = receiptURL(for: token)
            do {
                try data.write(to: destination, options: .withoutOverwriting)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: destination.path
                )
                return token
            } catch {
                try? FileManager.default.removeItem(at: destination)
            }
        }
        return ""
    }

    public func receipt(for token: String) -> RemovalReceiptArtifact? {
        guard Self.validToken(token),
              let data = try? Data(contentsOf: receiptURL(for: token)) else { return nil }
        return try? JSONDecoder().decode(RemovalReceiptArtifact.self, from: data)
    }

    public func consume(token: String, matching artifact: RemovalReceiptArtifact) -> Bool {
        guard Self.validToken(token) else { return false }
        let original = receiptURL(for: token)
        let claimed = directory.appendingPathComponent(".claimed-\(UUID().uuidString).json")
        guard rename(original.path, claimed.path) == 0 else { return false }

        guard let data = try? Data(contentsOf: claimed),
              let stored = try? JSONDecoder().decode(RemovalReceiptArtifact.self, from: data),
              stored == artifact else {
            if rename(claimed.path, original.path) != 0 {
                try? FileManager.default.removeItem(at: claimed)
            }
            return false
        }

        do {
            try FileManager.default.removeItem(at: claimed)
            return true
        } catch {
            return false
        }
    }

    private func receiptURL(for token: String) -> URL {
        directory.appendingPathComponent("\(token).json", isDirectory: false)
    }

    private static func validToken(_ token: String) -> Bool {
        token.utf8.count == 64 && token.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }

    private static func randomToken() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
