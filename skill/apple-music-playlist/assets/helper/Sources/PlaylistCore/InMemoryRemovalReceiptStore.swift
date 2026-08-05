import Foundation
import Security

public actor InMemoryRemovalReceiptStore: RemovalReceiptStore {
    private var receipts: [String: RemovalReceiptArtifact] = [:]

    public init() {}

    public func issue(_ artifact: RemovalReceiptArtifact) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        let token = Data(bytes).base64EncodedString()
        receipts[token] = artifact
        return token
    }

    public func receipt(for token: String) -> RemovalReceiptArtifact? {
        receipts[token]
    }

    public func consume(token: String, matching artifact: RemovalReceiptArtifact) -> Bool {
        guard receipts[token] == artifact else { return false }
        receipts.removeValue(forKey: token)
        return true
    }
}
