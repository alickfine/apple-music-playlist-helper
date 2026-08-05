import Foundation

public enum TextNormalization {
    private static let ignoredPunctuation = Set("，。！？、；：,.!?;:'\"“”‘’（）()【】[]".unicodeScalars)

    public static func normalize(_ input: String) -> String {
        let decomposed = input.decomposedStringWithCompatibilityMapping
        let foldedWhitespace = collapseWhitespace(decomposed)
        let lowercased = foldedWhitespace.localizedLowercase
        let withoutPunctuation = String(
            String.UnicodeScalarView(lowercased.unicodeScalars.filter { !ignoredPunctuation.contains($0) })
        )
        return collapseWhitespace(withoutPunctuation)
    }

    private static func collapseWhitespace(_ input: String) -> String {
        input
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
