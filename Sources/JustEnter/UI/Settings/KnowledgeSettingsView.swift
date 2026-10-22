import SwiftUI

struct KnowledgeSettingsView: View {
    @ObservedObject var store: KnowledgeStore
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.items) { item in
                        HStack {
                            Text(item.title.isEmpty ? "Untitled" : item.title)
                            Spacer()
                            if !item.enabled {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                        }
                        .tag(item.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                HStack(spacing: 12) {
                    Button {
                        let item = KnowledgeItem(title: "New snippet", content: "")
                        store.items.append(item)
                        selection = item.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        if let selection {
                            store.items.removeAll { $0.id == selection }
                            self.selection = store.items.first?.id
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 170, maxWidth: 230)

            if let selection, let index = store.items.firstIndex(where: { $0.id == selection }) {
                Form {
                    Section {
                        TextField("Title", text: bindingForItem(at: index).title)
                        Toggle("Include in prompts", isOn: bindingForItem(at: index).enabled)
                    }
                    Section("Content") {
                        TextEditor(text: bindingForItem(at: index).content)
                            .font(.system(size: 12))
                            .frame(minHeight: 220)
                    }
                    Section {
                        Text("Modes with “Knowledge base” enabled hand these snippets to the AI — team names, project glossaries, your email signature, anything that helps it write like you.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 380)
            } else {
                ContentUnavailableView(
                    "Knowledge base",
                    systemImage: "brain",
                    description: Text("Add snippets of standing context the AI should know while rewriting your dictation.")
                )
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func bindingForItem(at index: Int) -> Binding<KnowledgeItem> {
        Binding(
            get: { store.items.indices.contains(index) ? store.items[index] : KnowledgeItem(title: "", content: "") },
            set: { if store.items.indices.contains(index) { store.items[index] = $0 } }
        )
    }
}
