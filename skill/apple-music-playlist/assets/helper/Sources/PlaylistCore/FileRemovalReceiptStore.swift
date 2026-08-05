import Darwin
import Foundation
import Security

public enum FileRemovalReceiptStoreError: LocalizedError, Equatable, Sendable {
    case invalidDirectory

    public var errorDescription: String? {
        switch self {
        case .invalidDirectory:
            "收据目录必须由当前用户预先创建，且不得是符号链接或向其他用户开放。"
        }
    }
}

public actor FileRemovalReceiptStore: RemovalReceiptStore {
    private let directoryDescriptor: Int32

    public init(directory: URL) throws {
        self.directoryDescriptor = try Self.openValidatedDirectory(
            directory, effectiveUserID: geteuid()
        )
    }

    init(directory: URL, effectiveUserID: uid_t) throws {
        self.directoryDescriptor = try Self.openValidatedDirectory(
            directory, effectiveUserID: effectiveUserID
        )
    }

    deinit {
        _ = Darwin.close(directoryDescriptor)
    }

    public func issue(_ artifact: RemovalReceiptArtifact) -> String {
        guard directoryIsStillPrivate() else { return "" }
        guard let data = try? JSONEncoder().encode(artifact) else { return "" }
        for _ in 0..<4 {
            guard let token = Self.randomToken() else { return "" }
            let filename = receiptFilename(for: token)
            let descriptor = openat(
                directoryDescriptor,
                filename,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                mode_t(0o600)
            )
            guard descriptor >= 0 else { continue }

            let validFile = Self.validReceiptFile(descriptor, effectiveUserID: geteuid())
            let wrote = validFile && Self.writeAll(data, to: descriptor) && fsync(descriptor) == 0
            let closed = Darwin.close(descriptor) == 0
            guard wrote, closed else {
                _ = unlinkat(directoryDescriptor, filename, 0)
                continue
            }
            return token
        }
        return ""
    }

    public func receipt(for token: String) -> RemovalReceiptArtifact? {
        guard directoryIsStillPrivate(), Self.validToken(token) else { return nil }
        let descriptor = openat(directoryDescriptor, receiptFilename(for: token), O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { _ = Darwin.close(descriptor) }
        guard Self.validReceiptFile(descriptor, effectiveUserID: geteuid()),
              let data = Self.readAll(from: descriptor) else { return nil }
        return try? JSONDecoder().decode(RemovalReceiptArtifact.self, from: data)
    }

    public func consume(token: String, matching artifact: RemovalReceiptArtifact) -> Bool {
        guard directoryIsStillPrivate(), Self.validToken(token) else { return false }
        let filename = receiptFilename(for: token)
        let descriptor = openat(directoryDescriptor, filename, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        defer { _ = Darwin.close(descriptor) }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return false }
        defer { _ = flock(descriptor, LOCK_UN) }

        var openedMetadata = stat()
        guard fstat(descriptor, &openedMetadata) == 0,
              Self.validReceiptMetadata(openedMetadata, effectiveUserID: geteuid()),
              openedMetadata.st_nlink == 1,
              let data = Self.readAll(from: descriptor),
              let stored = try? JSONDecoder().decode(RemovalReceiptArtifact.self, from: data),
              stored == artifact else { return false }

        var pathMetadata = stat()
        guard fstatat(directoryDescriptor, filename, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0,
              pathMetadata.st_dev == openedMetadata.st_dev,
              pathMetadata.st_ino == openedMetadata.st_ino,
              unlinkat(directoryDescriptor, filename, 0) == 0 else { return false }
        return true
    }

    private func receiptFilename(for token: String) -> String {
        "\(token).json"
    }

    private func directoryIsStillPrivate() -> Bool {
        var metadata = stat()
        return fstat(directoryDescriptor, &metadata) == 0
            && Self.validDirectoryMetadata(metadata, effectiveUserID: geteuid())
    }

    private static func openValidatedDirectory(
        _ directory: URL,
        effectiveUserID: uid_t
    ) throws -> Int32 {
        let normalized = directory.standardizedFileURL
        var pathMetadata = stat()
        guard lstat(normalized.path, &pathMetadata) == 0,
              validDirectoryMetadata(pathMetadata, effectiveUserID: effectiveUserID) else {
            throw FileRemovalReceiptStoreError.invalidDirectory
        }

        let descriptor = open(normalized.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw FileRemovalReceiptStoreError.invalidDirectory }
        var openedMetadata = stat()
        guard fstat(descriptor, &openedMetadata) == 0,
              validDirectoryMetadata(openedMetadata, effectiveUserID: effectiveUserID),
              pathMetadata.st_dev == openedMetadata.st_dev,
              pathMetadata.st_ino == openedMetadata.st_ino else {
            _ = Darwin.close(descriptor)
            throw FileRemovalReceiptStoreError.invalidDirectory
        }
        return descriptor
    }

    private static func validDirectoryMetadata(_ metadata: stat, effectiveUserID: uid_t) -> Bool {
        (metadata.st_mode & S_IFMT) == S_IFDIR
            && metadata.st_uid == effectiveUserID
            && (metadata.st_mode & 0o077) == 0
    }

    private static func validReceiptFile(_ descriptor: Int32, effectiveUserID: uid_t) -> Bool {
        var metadata = stat()
        return fstat(descriptor, &metadata) == 0
            && validReceiptMetadata(metadata, effectiveUserID: effectiveUserID)
    }

    private static func validReceiptMetadata(_ metadata: stat, effectiveUserID: uid_t) -> Bool {
        (metadata.st_mode & S_IFMT) == S_IFREG
            && metadata.st_uid == effectiveUserID
            && (metadata.st_mode & 0o777) == 0o600
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }

    private static func readAll(from descriptor: Int32) -> Data? {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else { return nil }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { return nil }
            if count == 0 { return result }
            result.append(contentsOf: buffer[0..<count])
        }
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
