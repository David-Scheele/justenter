import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var search = ""
    @State private var selection: UUID?

    private var filtered: [HistoryRecord] {
        guard !search.isEmpty else { return store.records }
        return store.records.filter {
            $0.rawTranscript.localizedCaseInsensitiveContains(search)
                || $0.finalText.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selection) { record in
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.finalText)
                        .lineLimit(2)
                        .font(.callout)
                    HStack(spacing: 6) {
                        Text(record.modeName)
                        Text("·")
                        Text(record.appName)
                        Text("·")
                        Text(record.date, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(record.id)
            }
            .searchable(text: $search, prompt: "Search transcripts")
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let selection, let record = store.records.first(where: { $0.id == selection }) {
                HistoryDetailView(record: record, store: store)
            } else {
                ContentUnavailableView(
                    "Dictation history",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Every dictation is kept here — raw transcript and the AI's final text.")
                )
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    store.clear()
                    selection = nil
                } label: {
                    Label("Clear all", systemImage: "trash")
                }
                .disabled(store.records.isEmpty)
            }
        }
    }
}

private struct HistoryDetailView: View {
    let record: HistoryRecord
    let store: HistoryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text("\(record.modeName) · \(record.appName) · \(Int(record.duration))s of audio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.delete(record)
                    } label: {
                        Image(systemName: "trash")
                    }
                }

                transcriptBox(title: "Final text", text: record.finalText, prominent: true)
                if record.rawTranscript != record.finalText {
                    transcriptBox(title: "Raw transcript", text: record.rawTranscript, prominent: false)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func transcriptBox(title: String, text: String, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(prominent ? .primary : .secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
