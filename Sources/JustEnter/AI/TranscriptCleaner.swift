import Foundation

/// Deterministic fallback cleanup used when the local AI model is unavailable:
/// strips filler words and tidies the spacing/punctuation left behind.
enum TranscriptCleaner {
    private static let fillers = ["ähm", "äh", "uhm", "uh", "um", "ehm", "erm", "mhm", "hmm"]

    static func strip(_ text: String) -> String {
        var result = text
        for filler in fillers {
            let pattern = "(?i)(^|[\\s,])\(filler)([\\s,.!?]|$)"
            result = result.replacingOccurrences(of: pattern, with: "$1$2", options: .regularExpression)
        }
        // Collapse the leftovers: double spaces, space before punctuation, dangling commas.
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+([,.!?])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: ",\\s*,", with: ",", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
