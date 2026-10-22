import SwiftUI

struct VocabularySettingsView: View {
    @ObservedObject var store: VocabularyStore

    var body: some View {
        Form {
            Section {
                Text("Vocabulary biases the speech engines toward names and jargon they'd otherwise mangle, and tells the AI the exact spelling. Keep it focused — a handful of important terms works better than a huge list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Vocabulary") {
                ForEach($store.entries) { $entry in
                    HStack {
                        TextField("Term", text: $entry.phrase)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 140)
                        TextField("Common mis-hearings (comma-separated)", text: $entry.misspellings)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            store.entries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    store.entries.append(VocabularyEntry(phrase: ""))
                } label: {
                    Label("Add term", systemImage: "plus")
                }
            }

            Section("Replacements") {
                Text("Literal find → replace applied to every transcript, no AI involved. Great for “at sign” → @ or expanding snippets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach($store.replacements) { $replacement in
                    HStack {
                        TextField("Spoken text", text: $replacement.from)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                        TextField("Becomes", text: $replacement.to)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            store.replacements.removeAll { $0.id == replacement.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    store.replacements.append(Replacement(from: "", to: ""))
                } label: {
                    Label("Add replacement", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
    }
}
