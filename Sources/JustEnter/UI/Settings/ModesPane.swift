import SwiftUI
import AppKit

/// Modes, Superwhisper-style: a card list with the active dot; clicking a mode
/// drills into its editor (back chevron + title).
struct ModesPane: View {
    @ObservedObject var appState: AppState
    @State private var editingModeID: UUID?

    private var store: ModesStore { appState.modesStore }

    var body: some View {
        if let editingModeID, let index = store.modes.firstIndex(where: { $0.id == editingModeID }) {
            ModeEditorPane(
                appState: appState,
                mode: Binding(
                    get: { store.modes.indices.contains(index) ? store.modes[index] : Mode(name: "?") },
                    set: { store.update($0) }
                ),
                onBack: { self.editingModeID = nil },
                onDelete: {
                    if let mode = store.modes.first(where: { $0.id == editingModeID }) {
                        store.delete(mode)
                    }
                    self.editingModeID = nil
                }
            )
        } else {
            listView
        }
    }

    private var listView: some View {
        VStack(spacing: 0) {
            PaneScaffold(title: "Modes") {
                Button {
                    let mode = Mode(name: "New Mode", details: "Describe what this mode is for.")
                    store.add(mode)
                    editingModeID = mode.id
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(.quaternary.opacity(0.6), in: Circle())
                }
                .buttonStyle(.plain)
            } content: {
                ForEach(store.modes) { mode in
                    modeCard(mode)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text(appState.settings.modeSwitchHotkey.display)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                Text("Change active mode")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func modeCard(_ mode: Mode) -> some View {
        let isActive = mode.id == store.activeModeID
        Button {
            editingModeID = mode.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 14))
                    .frame(width: 22)
                Text(mode.name)
                    .font(.system(size: 13, weight: .medium))
                if isActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                }
                Spacer()
                if !mode.activationBundleIDs.isEmpty {
                    Text("\(mode.activationBundleIDs.count) app\(mode.activationBundleIDs.count == 1 ? "" : "s")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                }
                if mode.isAuto {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// Drill-in editor for one mode.
struct ModeEditorPane: View {
    @ObservedObject var appState: AppState
    @Binding var mode: Mode
    let onBack: () -> Void
    let onDelete: () -> Void
    @State private var newBundleID = ""
    @State private var confirmDelete = false
    @State private var generating = false
    @State private var confirmGenerate = false
    @State private var generateError: String?

    private let symbols = [
        "waveform", "text.quote", "bubble.left.and.bubble.right", "envelope",
        "note.text", "terminal", "doc.text", "list.bullet", "sparkles",
        "keyboard", "message", "globe", "book", "pencil.line", "wand.and.stars",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Image(systemName: mode.symbol)
                    .font(.system(size: 14))
                Text(mode.name)
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                if mode.id != appState.modesStore.activeModeID {
                    Button("Make Active") {
                        appState.modesStore.select(mode, manual: true)
                    }
                    .controlSize(.small)
                } else {
                    Label("Active", systemImage: "circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 26)
            // Clears the (invisible) unified-toolbar strip, which swallows clicks.
            .padding(.top, 56)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identityCard
                    if mode.isAuto {
                        autoCard
                    } else {
                        aiCard
                        contextCard
                        appsCard
                    }
                    deliveryCard
                    if !mode.isAuto {
                        Button("Delete Mode…", role: .destructive) {
                            confirmDelete = true
                        }
                        .confirmationDialog("Delete “\(mode.name)”?", isPresented: $confirmDelete) {
                            Button("Delete", role: .destructive) { onDelete() }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 24)
            }
        }
    }

    private var identityCard: some View {
        SettingsCard {
            CardRow(title: "Name") {
                TextField("Name", text: $mode.name)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 220)
            }
            CardDivider()
            CardRow(title: "Icon") {
                Picker("", selection: $mode.symbol) {
                    ForEach(symbols, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
            }
            CardDivider()
            CardRow(title: "Description") {
                TextField("What is this mode for?", text: $mode.details)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var autoCard: some View {
        SettingsCard {
            Text("Auto picks one of your other modes for every dictation: a mode whose app list matches the frontmost app wins; otherwise the local AI routes by what you said; otherwise the transcript is just cleaned up. Tune the other modes — Auto follows them.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneSectionTitle("AI")
            SettingsCard {
                CardRow(title: "Restyle with AI", subtitle: "Fillers and self-corrections are always cleaned up, even when off.") {
                    Toggle("", isOn: $mode.aiEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if mode.aiEnabled {
                    CardDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Instructions")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            if generating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button {
                                    if mode.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        generatePrompt()
                                    } else {
                                        confirmGenerate = true
                                    }
                                } label: {
                                    Label("Generate from description", systemImage: "sparkles")
                                        .font(.system(size: 11))
                                }
                                .controlSize(.small)
                                .disabled(mode.details.trimmingCharacters(in: .whitespaces).isEmpty)
                                .help(mode.details.isEmpty
                                    ? "Add a description above first — the AI writes the instructions from it."
                                    : "Let the local AI write the instructions from the name and description.")
                                .confirmationDialog(
                                    "Replace the current instructions?",
                                    isPresented: $confirmGenerate
                                ) {
                                    Button("Replace", role: .destructive) { generatePrompt() }
                                }
                            }
                        }
                        TextEditor(text: $mode.prompt)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                            .padding(10)
                            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                            )
                            .overlay(alignment: .topLeading) {
                                if mode.prompt.isEmpty {
                                    Text("How should the AI rewrite dictations in this mode? E.g. “Format as a short, friendly chat message.”")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 10)
                                        .padding(.leading, 14)
                                        .allowsHitTesting(false)
                                }
                            }
                        if let generateError {
                            Text(generateError)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }
            }
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneSectionTitle("Context for the AI")
            SettingsCard {
                CardRow(title: "Active app name") {
                    Toggle("", isOn: $mode.includeActiveApp).labelsHidden().toggleStyle(.switch)
                }
                CardDivider()
                CardRow(title: "Selected text", subtitle: "Needs Accessibility access.") {
                    Toggle("", isOn: $mode.includeSelectedText).labelsHidden().toggleStyle(.switch)
                }
                CardDivider()
                CardRow(title: "Clipboard contents") {
                    Toggle("", isOn: $mode.includeClipboard).labelsHidden().toggleStyle(.switch)
                }
                CardDivider()
                CardRow(title: "User vocabulary") {
                    Toggle("", isOn: $mode.useVocabulary).labelsHidden().toggleStyle(.switch)
                }
                CardDivider()
                CardRow(title: "Knowledge base") {
                    Toggle("", isOn: $mode.useKnowledgeBase).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneSectionTitle("Activate for apps")
            SettingsCard {
                ForEach(mode.activationBundleIDs, id: \.self) { bundleID in
                    CardRow(title: appName(for: bundleID) ?? bundleID, subtitle: bundleID) {
                        Button {
                            mode.activationBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    CardDivider()
                }
                CardRow(title: "Add app") {
                    HStack(spacing: 8) {
                        Menu("Running apps") {
                            ForEach(runningApps(), id: \.bundleID) { app in
                                Button(app.name) {
                                    if !mode.activationBundleIDs.contains(app.bundleID) {
                                        mode.activationBundleIDs.append(app.bundleID)
                                    }
                                }
                            }
                        }
                        .frame(width: 130)
                        TextField("bundle id", text: $newBundleID)
                            .frame(width: 150)
                            .onSubmit { addBundleID() }
                        Button("Add") { addBundleID() }
                            .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private var deliveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneSectionTitle("Language & delivery")
            SettingsCard {
                CardRow(title: "Language") {
                    Picker("", selection: $mode.language) {
                        Text("App default").tag("")
                        Text("Automatic").tag("auto")
                        ForEach(["en-US", "de-DE", "fr-FR", "es-ES", "it-IT"], id: \.self) { code in
                            Text(Locale.current.localizedString(forIdentifier: code) ?? code).tag(code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                CardDivider()
                CardRow(title: "Restore clipboard after pasting") {
                    Toggle("", isOn: $mode.restoreClipboard).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private func generatePrompt() {
        guard !generating else { return }
        generating = true
        generateError = nil
        Task {
            do {
                mode.prompt = try await appState.generateModePrompt(name: mode.name, description: mode.details)
            } catch {
                generateError = "Couldn't generate: \(error.localizedDescription)"
            }
            generating = false
        }
    }

    private func addBundleID() {
        let trimmed = newBundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !mode.activationBundleIDs.contains(trimmed) else { return }
        mode.activationBundleIDs.append(trimmed)
        newBundleID = ""
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
