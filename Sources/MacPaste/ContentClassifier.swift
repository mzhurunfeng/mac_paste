import CryptoKit
import Foundation

enum ContentClassifier {
    static func classifyText(_ text: String) -> ClipboardItemType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isColor(trimmed) {
            return .color
        }
        if isLink(trimmed) {
            return .link
        }
        return .text
    }

    static func title(for text: String, type: ClipboardItemType) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = trimmed
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        if singleLine.isEmpty {
            return type.label
        }
        return String(singleLine.prefix(120))
    }

    static func sha256Hex(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func textMetrics(_ text: String) -> (chars: Int, words: Int, bytes: Int) {
        let words = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
        return (text.count, words, text.data(using: .utf8)?.count ?? 0)
    }

    private static func isLink(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private static func isColor(_ text: String) -> Bool {
        let hexPattern = #"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#
        let rgbPattern = #"^rgba?\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\)$"#
        return text.range(of: hexPattern, options: .regularExpression) != nil ||
            text.range(of: rgbPattern, options: .regularExpression) != nil
    }
}
