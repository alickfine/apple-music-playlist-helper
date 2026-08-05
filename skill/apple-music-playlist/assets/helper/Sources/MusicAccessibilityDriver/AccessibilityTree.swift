import Foundation

public struct AccessibilityNodeSnapshot: Equatable, Sendable {
    public let identifier: String?
    public let role: String?
    public let title: String?
    public let description: String?
    public let children: [AccessibilityNodeSnapshot]

    public init(
        identifier: String? = nil,
        role: String? = nil,
        title: String? = nil,
        description: String? = nil,
        children: [AccessibilityNodeSnapshot] = []
    ) {
        self.identifier = identifier
        self.role = role
        self.title = title
        self.description = description
        self.children = children
    }
}

public struct AccessibilityPath: Equatable, Hashable, Sendable {
    public let indices: [Int]
    public init(indices: [Int]) { self.indices = indices }
}

public protocol AccessibilityProviding: Sendable {
    func isAuthorized() -> Bool
    func musicTree() throws -> AccessibilityNodeSnapshot
    func press(path: AccessibilityPath) throws
}

public protocol URLOpening: Sendable {
    func openInMusic(_ url: URL) async throws
}
