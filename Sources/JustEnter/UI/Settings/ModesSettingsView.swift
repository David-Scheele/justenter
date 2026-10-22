import SwiftUI
import AppKit

struct ModesSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selection: UUID?

    private var store: ModesStore { appState.modesStore }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.modes) { mode in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mode.name)
                                if mode.id == store.activeModeID {
                                    Text("Active")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: mode.symbol)
                        }
                        .tag(mode.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                HStack(spacing: 12) {
                    Button {
                        let mode = Mode(name: "New Mode", details: "Describe what this mode is for.")
                        store.add(mode)
                        selection = mode.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        if let selection, let mode = store.modes.first(where: { $0.id == selection }) {
                            store.delete(mode)
                            self.selection = store.modes.first?.id
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(
                        selection == nil || store.modes.count <= 1
                            || store.modes.first(where: { $0.id == selection })?.isAuto == true
                    )
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 180, maxWidth: 240)

            if let selection, let index = store.modes.firstIndex(where: { $0.id == selection }) {
                ModeEditorView(mode: bindingForMode(at: index), store: store)
                    .frame(minWidth: 380)
            } else {
                ContentUnavailableView("Select a mode", systemImage: "square.grid.2x2")
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = store.activeModeID }
    }

    private func bindingForMode(at index: Int) -> Binding<Mode> {
        Binding(
            get: { store.modes.indices.contains(index) ? store.modes[index] : Mode(name: "?") },
            set: { store.update($0) }
        )
    }
}

struct ModeEditorView: View {
    @Binding var mode: Mode
    let store: ModesStore
    @State private var newBundleID = ""

    private let symbols = [
        "waveform", "text.quote", "bubble.left.and.bubble.right", "envelope",
        "note.text", "terminal", "doc.text", "list.bullet", "sparkles",
        "keyboard", "message", "globe", "book", "pencil.line",
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $mode.name)
                Picker("Icon", selection: $mode.symbol) {
                    ForEach(symbols, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
                TextField("Description", text: $mode.details)
                Button("Make active") {
                    store.select(mode, manual: true)
                }
                .disabled(store.activeModeID == mode.id)
            }

            if mode.isAuto {
                Section("Auto mode") {
                    Text("This mode picks one of your other modes for every dictation: a mode whose app list matches the frontmost app wins; otherwise the local AI routes by what you said; otherwise the transcript is just cleaned up. There is nothing to configure here — tune the other modes instead.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if !mode.isAuto {
            Section("AI enhancement") {
                Toggle("Restyle with AI", isOn: $mode.aiEnabled)
                Text("Filler words and self-corrections are always cleaned up, even with this off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if mode.aiEnabled {
                    TextEditor(text: $mode.prompt)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if mode.prompt.isEmpty {
                                Text("Instructions for the AI, e.g. “Clean up the dictation and format it as a polite email.”")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            if mode.aiEnabled {
                Section("Context for the AI") {
                    Toggle("Active app name", isOn: $mode.includeActiveApp)
                    Toggle("Selected text (needs Accessibility)", isOn: $mode.includeSelectedText)
                    Toggle("Clipboard contents", isOn: $mode.includeClipboard)
                    Toggle("User vocabulary", isOn: $mode.useVocabulary)
                    Toggle("Knowledge base", isOn: $mode.useKnowledgeBase)
                }
            }

            Section("Auto-activate in apps") {
                ForEach(mode.activationBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(appName(for: bundleID) ?? bundleID)
                        Spacer()
                        Text(bundleID)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Button {
                            mode.activationBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Add running app…") {
                    ForEach(runningApps(), id: \.bundleID) { app in
                        Button(app.name) {
                            if !mode.activationBundleIDs.contains(app.bundleID) {
                                mode.activationBundleIDs.append(app.bundleID)
                            }
                        }
                    }
                }
                HStack {
                    TextField("Or enter a bundle ID, e.g. com.apple.Notes", text: $newBundleID)
                    Button("Add") {
                        let trimmed = newBundleID.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty, !mode.activationBundleIDs.contains(trimmed) {
                            mode.activationBundleIDs.append(trimmed)
                            newBundleID = ""
                        }
                    }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            }

            Section("Language & delivery") {
                TextField("Language override (auto, de-DE, en-US… — empty = app default)", text: $mode.language)
                Toggle("Restore previous clipboard after pasting", isOn: $mode.restoreClipboard)
            }
        }
        .formStyle(.grouped)
    }

    private func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func runningApps() -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (bundleID: bundleID, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
