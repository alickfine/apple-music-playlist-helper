import Foundation

public enum AccessibilityMatcher {
    public static func trackMoreButton(
        catalogID: String,
        in root: AccessibilityNodeSnapshot
    ) -> AccessibilityPath? {
        findCatalogContainer(catalogID: catalogID, node: root, path: [])
    }

    public static func playlistMenuItem(
        named name: String,
        in root: AccessibilityNodeSnapshot
    ) -> AccessibilityPath? {
        find(node: root, path: []) { node in
            node.role == "AXMenuItem" && node.title == name
        }
    }

    private static func findCatalogContainer(
        catalogID: String,
        node: AccessibilityNodeSnapshot,
        path: [Int]
    ) -> AccessibilityPath? {
        if nodeContainsExactNumericToken(node, token: catalogID),
           let morePath = find(node: node, path: path, predicate: isMoreButton) {
            return morePath
        }
        for (index, child) in node.children.enumerated() {
            if let match = findCatalogContainer(catalogID: catalogID, node: child, path: path + [index]) {
                return match
            }
        }
        return nil
    }

    private static func find(
        node: AccessibilityNodeSnapshot,
        path: [Int],
        predicate: (AccessibilityNodeSnapshot) -> Bool
    ) -> AccessibilityPath? {
        if predicate(node) { return AccessibilityPath(indices: path) }
        for (index, child) in node.children.enumerated() {
            if let match = find(node: child, path: path + [index], predicate: predicate) {
                return match
            }
        }
        return nil
    }

    private static func nodeContainsExactNumericToken(_ node: AccessibilityNodeSnapshot, token: String) -> Bool {
        [node.identifier, node.title, node.description]
            .compactMap { $0 }
            .flatMap(numericTokens(in:))
            .contains(token)
    }

    private static func numericTokens(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isNumber }).map(String.init)
    }

    private static func isMoreButton(_ node: AccessibilityNodeSnapshot) -> Bool {
        guard node.role == "AXButton" else { return false }
        return [node.identifier, node.title, node.description]
            .compactMap { $0?.localizedLowercase }
            .contains { $0 == "更多" || $0 == "more" || $0.contains("more-button") }
    }
}
