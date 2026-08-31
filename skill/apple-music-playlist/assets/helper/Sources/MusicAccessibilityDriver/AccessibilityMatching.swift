import Foundation

public enum AccessibilityMatcher {
    public static func menu(in root: AccessibilityNodeSnapshot) -> AccessibilityPath? {
        findPopupMenu(node: root, path: [], insideMenuBar: false)
    }

    private static func findPopupMenu(
        node: AccessibilityNodeSnapshot,
        path: [Int],
        insideMenuBar: Bool
    ) -> AccessibilityPath? {
        let nestedInMenuBar = insideMenuBar || node.role == "AXMenuBar"
        if node.role == "AXMenu" && !nestedInMenuBar { return AccessibilityPath(indices: path) }
        for (index, child) in node.children.enumerated() {
            if let match = findPopupMenu(
                node: child,
                path: path + [index],
                insideMenuBar: nestedInMenuBar
            ) { return match }
        }
        return nil
    }

    public static func trackMoreButton(
        catalogID: String,
        in root: AccessibilityNodeSnapshot
    ) -> AccessibilityPath? {
        findCatalogContainer(catalogID: catalogID, node: root, path: [])
    }

    public static func trackContainer(
        catalogID: String,
        in root: AccessibilityNodeSnapshot
    ) -> AccessibilityPath? {
        findExactTrackContainer(catalogID: catalogID, node: root, path: [])
    }

    private static func findExactTrackContainer(
        catalogID: String,
        node: AccessibilityNodeSnapshot,
        path: [Int]
    ) -> AccessibilityPath? {
        if nodeContainsExactNumericToken(node, token: catalogID),
           find(node: node, path: [], predicate: isMoreButton) != nil {
            return AccessibilityPath(indices: path)
        }
        for (index, child) in node.children.enumerated() {
            if let match = findExactTrackContainer(catalogID: catalogID, node: child, path: path + [index]) {
                return match
            }
        }
        return nil
    }

    public static func sidebarPlaylistRow(
        named name: String,
        in root: AccessibilityNodeSnapshot
    ) -> AccessibilityPath? {
        findSidebarDestination(named: name, node: root, path: [], nearestRow: nil)
    }

    private static func findSidebarDestination(
        named name: String,
        node: AccessibilityNodeSnapshot,
        path: [Int],
        nearestRow: AccessibilityPath?
    ) -> AccessibilityPath? {
        let row = node.role == "AXRow" ? AccessibilityPath(indices: path) : nearestRow
        let isExact = [node.title, node.description, node.value]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(name)
        if isExact { return row ?? AccessibilityPath(indices: path) }
        for (index, child) in node.children.enumerated() {
            if let match = findSidebarDestination(
                named: name,
                node: child,
                path: path + [index],
                nearestRow: row
            ) { return match }
        }
        return nil
    }

    public static func playlistMenuItem(
        named name: String,
        in root: AccessibilityNodeSnapshot
    ) -> AccessibilityPath? {
        find(node: root, path: []) { node in
            node.role == "AXMenuItem" && node.title == name
        }
    }

    public static func searchField(in root: AccessibilityNodeSnapshot) -> AccessibilityPath? {
        find(node: root, path: []) { node in
            if node.role == "AXSearchField" { return true }
            guard node.role == "AXTextField" else { return false }
            return [node.identifier, node.title, node.description]
                .compactMap { $0?.localizedLowercase }
                .contains { $0.contains("search") || $0.contains("搜索") }
        }
    }

    public static func readySearchField(in root: AccessibilityNodeSnapshot) -> AccessibilityPath? {
        let isSearchScreen = find(node: root, path: []) { node in
            guard let identifier = node.identifier else { return false }
            return identifier.contains("TopSearchLockup")
                || identifier.contains("SearchLandingBrickLockup")
        } != nil
        let hasSearchScope = find(node: root, path: []) { node in
            node.identifier == "UIA.Music.Search.Scope"
        } != nil
        guard isSearchScreen || hasSearchScope else { return nil }
        return searchField(in: root)
    }

    public static func sidebarSearchRow(in root: AccessibilityNodeSnapshot) -> AccessibilityPath? {
        find(node: root, path: []) { node in
            guard node.role == "AXRow" else { return false }
            return [node.title, node.description]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase }
                .contains { $0 == "搜索" || $0 == "search" }
        }
    }

    public static func topSearchResult(
        catalogID: String,
        in root: AccessibilityNodeSnapshot
    ) -> AccessibilityPath? {
        find(node: root, path: []) { node in
            guard node.identifier?.contains("TopSearchLockup") == true else { return false }
            return nodeContainsExactNumericToken(node, token: catalogID)
        }
    }

    public static func albumSearchResult(
        albumID: String,
        in root: AccessibilityNodeSnapshot
    ) -> AccessibilityPath? {
        find(node: root, path: []) { node in
            guard let identifier = node.identifier,
                  identifier.contains("TopSearchLockup") || identifier.contains("SquareLockup") else {
                return false
            }
            return nodeContainsExactNumericToken(node, token: albumID)
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
