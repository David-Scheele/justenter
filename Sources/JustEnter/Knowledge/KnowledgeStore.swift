import Foundation
import Combine

/// A snippet of background knowledge Claude can use while cleaning up dictation —
/// project names, people, terminology, standing context.
struct KnowledgeItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var content: String
    var enabled: Bool = true
}

@MainActor
final class KnowledgeStore: ObservableObject {
    @Published var items: [KnowledgeItem] {
        didSet { Persistence.save(items, to: "knowledge.json") }
    }

    init() {
        items = Persistence.load([KnowledgeItem].self, from: "knowledge.json") ?? []
    }

    var promptSection: String {
        let active = items.filter { $0.enabled && !$0.content.isEmpty }
        guard !active.isEmpty else { return "" }
        let blocks = active.map { "### \($0.title)\n\($0.content)" }.joined(separator: "\n\n")
        return "Background knowledge about the speaker and their work:\n\n\(blocks)"
    }
}
