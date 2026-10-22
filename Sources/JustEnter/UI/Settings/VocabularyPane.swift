import SwiftUI

/// Vocabulary, Superwhisper-style: one add bar on top ("Add word" / "Replace
/// with…"), a single mixed list below — plain words and "a → b" replacements.
struct VocabularyPane: View {
    @ObservedObject var store: VocabularyStore
    @State private var newText = ""
    @State private var replacementText = ""
    @State private var showReplacement = false

    private enum Row: Identifiable {
        case word(VocabularyEntry)
        case replacement(Replacement)

        var id: String {
            switch self {
            case .word(let entry): return "w-\(entry.id)"
            case .replacement(let replacement): return "r-\(replacement.id)"
            }
        }

        var sortKey: String {
            switch self {
            case .word(let entry): return entry.phrase.lowercased()
            case .replacement(let replacement): return replacement.from.lowercased()
            }
        }
    }

    private var rows: [Row] {
        (store.entries.map(Row.word) + store.replacements.map(Row.replacement))
            .sorted { $0.sortKey < $1.sortKey }
    }

    var body: some View {
        PaneScaffold(title: "Vocabulary") {
            SettingsCard {
                HStack(spacing: 10) {
                    TextField(showReplacement ? "Spoken text" : "New word or replacement", text: $newText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit { addWord() }
                    if showReplacement {
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                        TextField("Replace with", text: $replacementText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onSubmit { addReplacement() }
                        Button("Add") { addReplacement() }
                            .controlSize(.small)
                            .disabled(newText.isEmpty || replacementText.isEmpty)
                        Button {
                            showReplacement = false
                            replacementText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button("Add word") { addWord() }
                            .controlSize(.small)
                            .disabled(newText.isEmpty)
                        Button("Replace with…") { showReplacement = true }
                            .controlSize(.small)
                            .disabled(newText.isEmpty)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            Text("Words bias the speech models toward names and jargon and tell the AI the exact spelling. Replacements are applied literally to every transcript — “at sign” → @.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            SettingsCard {
                if rows.isEmpty {
                    Text("Nothing yet — add the names and terms that get misheard.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            CardDivider()
                        }
                        rowView(row)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 10) {
            switch row {
            case .word(let entry):
                Text(entry.phrase)
                    .font(.system(size: 13))
                if !entry.misspellings.isEmpty {
                    Text("misheard as: \(entry.misspellings)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            case .replacement(let replacement):
                Text(replacement.from)
                    .font(.system(size: 13))
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.secondary)
                Text(replacement.to)
                    .font(.system(size: 13))
            }
            Spacer()
            Button {
                delete(row)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contextMenu {
            if case .word(let entry) = row {
                Button("Convert to replacement…") {
                    store.entries.removeAll { $0.id == entry.id }
                    newText = entry.phrase
                    showReplacement = true
                }
            }
        }
    }

    private func addWord() {
        let trimmed = newText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.entries.append(VocabularyEntry(phrase: trimmed))
        newText = ""
    }

    private func addReplacement() {
        let from = newText.trimmingCharacters(in: .whitespaces)
        let to = replacementText.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty, !to.isEmpty else { return }
        store.replacements.append(Replacement(from: from, to: to))
        newText = ""
        replacementText = ""
        showReplacement = false
    }

    private func delete(_ row: Row) {
        switch row {
        case .word(let entry):
            store.entries.removeAll { $0.id == entry.id }
        case .replacement(let replacement):
            store.replacements.removeAll { $0.id == replacement.id }
        }
    }
}

/// Knowledge base pane in the same card style.
struct KnowledgePane: View {
    @ObservedObject var store: KnowledgeStore

    var body: some View {
        PaneScaffold(title: "Knowledge") {
            Button {
                store.items.append(KnowledgeItem(title: "New snippet", content: ""))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.quaternary.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
        } content: {
            Text("Standing context the AI can use while rewriting — team names, project glossaries, your signature. Modes opt in via “Knowledge base”.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ForEach($store.items) { $item in
                SettingsCard {
                    CardRow(title: "Title") {
                        TextField("Title", text: $item.title)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 240)
                    }
                    CardDivider()
                    CardRow(title: "Include in prompts") {
                        Toggle("", isOn: $item.enabled).labelsHidden().toggleStyle(.switch)
                    }
                    CardDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        TextEditor(text: $item.content)
                            .font(.system(size: 12))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        Button("Remove snippet", role: .destructive) {
                            store.items.removeAll { $0.id == item.id }
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }
            }
        }
    }
}
