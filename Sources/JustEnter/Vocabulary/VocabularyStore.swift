import Foundation
import Combine

/// A word or phrase the speech engines tend to get wrong, with optional
/// misspellings that are corrected after transcription.
struct VocabularyEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// The correct spelling, e.g. "innosabi", "Anthropic", "Kubernetes".
    var phrase: String
    /// Common wrong transcriptions to auto-replace, e.g. "inno sabi, inosabi".
    var misspellings: String = ""
}

/// A plain text replacement applied to every transcript (e.g. "at sign" → "@").
struct Replacement: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var from: String
    var to: String
    var caseSensitive: Bool = false
}

@MainActor
final class VocabularyStore: ObservableObject {
    @Published var entries: [VocabularyEntry] {
        didSet { Persistence.save(entries, to: "vocabulary.json") }
    }
    @Published var replacements: [Replacement] {
        didSet { Persistence.save(replacements, to: "replacements.json") }
    }

    init() {
        entries = Persistence.load([VocabularyEntry].self, from: "vocabulary.json") ?? []
        replacements = Persistence.load([Replacement].self, from: "replacements.json") ?? []
    }

    /// Phrases handed to the speech engine for biasing / prompting.
    var phrases: [String] {
        entries.map(\.phrase).filter { !$0.isEmpty }
    }

    /// Fixes misspellings and applies user replacements to a raw transcript.
    func apply(to text: String) -> String {
        var result = text
        for entry in entries where !entry.phrase.isEmpty {
            for wrong in entry.misspellings.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !wrong.isEmpty {
                result = result.replacingOccurrences(of: wrong, with: entry.phrase, options: [.caseInsensitive])
            }
        }
        for replacement in replacements where !replacement.from.isEmpty {
            let options: String.CompareOptions = replacement.caseSensitive ? [] : [.caseInsensitive]
            result = result.replacingOccurrences(of: replacement.from, with: replacement.to, options: options)
        }
        return result
    }

    /// Vocabulary block injected into Claude's system prompt.
    var promptSection: String {
        guard !entries.isEmpty else { return "" }
        let list = entries.map { entry in
            entry.misspellings.isEmpty
                ? "- \(entry.phrase)"
                : "- \(entry.phrase) (often misheard as: \(entry.misspellings))"
        }.joined(separator: "\n")
        return """
        The speaker uses these names and terms — always spell them exactly like this, \
        and fix likely mis-transcriptions of them:
        \(list)
        """
    }
}
