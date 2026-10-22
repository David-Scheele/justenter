import Foundation
import Combine

struct HistoryRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var modeName: String
    var appName: String
    var duration: TimeInterval
    var rawTranscript: String
    var finalText: String
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [HistoryRecord] {
        didSet { Persistence.save(records, to: "history.json") }
    }

    private let maxRecords = 200

    init() {
        records = Persistence.load([HistoryRecord].self, from: "history.json") ?? []
    }

    func add(_ record: HistoryRecord) {
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records.removeLast(records.count - maxRecords)
        }
    }

    func delete(_ record: HistoryRecord) {
        records.removeAll { $0.id == record.id }
    }

    func clear() {
        records.removeAll()
    }
}
