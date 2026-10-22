import SwiftUI

/// Models library, Superwhisper-style: one table for voice (speech-to-text) and
/// language (AI rewriting) models — star marks the active one, trailing button
/// downloads or deletes, dashes show speed/accuracy.
struct ModelsLibraryPane: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings = AppSettings.shared

    @State private var installedOllama: [LocalAIService.OllamaModel]?
    @State private var ollamaReachable = false
    @State private var busyModel: String?
    @State private var busyProgress: Double?
    @State private var busyLabel = ""
    @State private var errorMessage: String?
    @State private var hoveredRowID: String?

    private enum ModelKind {
        case voice
        case language
    }

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let kind: ModelKind
        let speed: Int
        let accuracy: Int
        let sizeLabel: String
        let builtIn: Bool
        let note: String?
    }

    private static let voiceEntries: [Entry] = [
        Entry(id: "apple", name: "Apple Speech", kind: .voice, speed: 5, accuracy: 4, sizeLabel: "built-in", builtIn: true, note: "Streams live, managed by macOS"),
        Entry(id: "tiny", name: "Whisper Tiny", kind: .voice, speed: 5, accuracy: 1, sizeLabel: "75 MB", builtIn: false, note: nil),
        Entry(id: "base", name: "Whisper Base", kind: .voice, speed: 5, accuracy: 2, sizeLabel: "145 MB", builtIn: false, note: nil),
        Entry(id: "small", name: "Whisper Small", kind: .voice, speed: 4, accuracy: 3, sizeLabel: "465 MB", builtIn: false, note: nil),
        Entry(id: "medium", name: "Whisper Medium", kind: .voice, speed: 3, accuracy: 4, sizeLabel: "1.5 GB", builtIn: false, note: nil),
        Entry(id: "large-v3-v20240930_626MB", name: "Whisper Large v3", kind: .voice, speed: 2, accuracy: 4, sizeLabel: "626 MB", builtIn: false, note: "Compressed"),
        Entry(id: "large-v3-v20240930_turbo", name: "Whisper Large v3 Turbo", kind: .voice, speed: 2, accuracy: 5, sizeLabel: "1.6 GB", builtIn: false, note: nil),
    ]

    private static let languageCatalog: [Entry] = [
        Entry(id: "apple-intelligence", name: "Apple Intelligence", kind: .language, speed: 4, accuracy: 3, sizeLabel: "built-in", builtIn: true, note: "On-device foundation model"),
        Entry(id: "llama3.2:1b", name: "Llama 3.2 1B", kind: .language, speed: 5, accuracy: 2, sizeLabel: "0.8 GB", builtIn: false, note: "Nano"),
        Entry(id: "llama3.2:3b", name: "Llama 3.2 3B", kind: .language, speed: 5, accuracy: 3, sizeLabel: "2 GB", builtIn: false, note: "Nano"),
        Entry(id: "qwen3:4b", name: "Qwen 3 4B", kind: .language, speed: 4, accuracy: 3, sizeLabel: "2.6 GB", builtIn: false, note: "Small"),
        Entry(id: "gemma3:4b", name: "Gemma 3 4B", kind: .language, speed: 4, accuracy: 4, sizeLabel: "3.3 GB", builtIn: false, note: "Small · strong German"),
        Entry(id: "qwen3:8b", name: "Qwen 3 8B", kind: .language, speed: 3, accuracy: 4, sizeLabel: "5.2 GB", builtIn: false, note: "Medium"),
        Entry(id: "gemma3:12b", name: "Gemma 3 12B", kind: .language, speed: 2, accuracy: 5, sizeLabel: "8.1 GB", builtIn: false, note: "Medium"),
        Entry(id: "deepseek-r1:8b", name: "DeepSeek R1 8B", kind: .language, speed: 2, accuracy: 4, sizeLabel: "5.2 GB", builtIn: false, note: "Research · reasoning"),
        Entry(id: "gpt-oss:20b", name: "GPT-OSS 20B", kind: .language, speed: 1, accuracy: 5, sizeLabel: "13 GB", builtIn: false, note: "Large · heavy on RAM"),
    ]

    /// Catalog plus any other models installed in Ollama.
    private var languageEntries: [Entry] {
        var entries = Self.languageCatalog
        for model in installedOllama ?? [] where !entries.contains(where: { $0.id == model.name }) {
            entries.append(Entry(
                id: model.name, name: model.name, kind: .language,
                speed: 3, accuracy: 3,
                sizeLabel: String(format: "%.1f GB", model.sizeGB),
                builtIn: false, note: "Installed via Ollama"
            ))
        }
        return entries
    }

    var body: some View {
        PaneScaffold(title: "Models library") {
            if let busyModel {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 5) {
                        if let busyProgress {
                            ProgressView(value: busyProgress)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("\(busyModel): \(busyLabel)\(busyProgress.map { " — \(Int($0 * 100))%" } ?? "")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            PaneSectionTitle("Voice — speech to text")
            SettingsCard {
                header
                ForEach(Self.voiceEntries) { entry in
                    CardDivider()
                    row(entry)
                }
            }

            PaneSectionTitle("Language — AI rewriting")
            if !ollamaReachable {
                Text("Models other than Apple Intelligence run through Ollama, which isn't reachable — install and start it: `brew install ollama && brew services start ollama`.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            SettingsCard {
                header
                ForEach(languageEntries) { entry in
                    CardDivider()
                    row(entry)
                }
            }
        }
        .task { await refreshOllama() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Model").frame(width: 240, alignment: .leading)
            Text("Type").frame(width: 36, alignment: .center)
            Text("Speed").frame(width: 70, alignment: .leading)
            Text("Accuracy").frame(width: 70, alignment: .leading)
            Spacer()
            Text("Size / Action")
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        let active = isActive(entry)
        let installed = isInstalled(entry)
        let selectable = installed || entry.builtIn
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                // Radio indicator: one active model per group.
                Image(systemName: active ? "inset.filled.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.system(size: 13, weight: active ? .semibold : .regular))
                        if active {
                            Text("Active")
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.accentColor.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if let note = entry.note {
                        Text(note)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 240, alignment: .leading)

            Image(systemName: entry.kind == .voice ? "waveform" : "text.alignleft")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .center)

            RatingDashes(value: entry.speed).frame(width: 70, alignment: .leading)
            RatingDashes(value: entry.accuracy).frame(width: 70, alignment: .leading)
            Spacer()

            HStack(spacing: 8) {
                Text(entry.sizeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if entry.builtIn {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("Built into macOS")
                } else if installed {
                    Button {
                        delete(entry)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(active || busyModel != nil)
                    .help(active ? "Active model — pick another first" : "Delete from disk")
                } else {
                    Button {
                        download(entry)
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .disabled(busyModel != nil || (entry.kind == .language && !ollamaReachable))
                    .help("Download")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            active ? AnyShapeStyle(Color.accentColor.opacity(0.08))
                : hoveredRowID == entry.id && selectable ? AnyShapeStyle(.quaternary.opacity(0.5))
                : AnyShapeStyle(.clear)
        )
        // The whole row selects the model; the trailing buttons still win on click.
        .contentShape(Rectangle())
        .onTapGesture {
            if selectable, !active {
                select(entry)
            }
        }
        .onHover { hovering in
            hoveredRowID = hovering ? entry.id : (hoveredRowID == entry.id ? nil : hoveredRowID)
        }
        .help(selectable
            ? (active ? "Active model" : "Click to make this the active model")
            : "Download first, then click to activate")
    }

    // MARK: - State helpers

    private func isActive(_ entry: Entry) -> Bool {
        switch entry.kind {
        case .voice:
            if entry.builtIn {
                return settings.speechEngine == .apple
            }
            return settings.speechEngine == .whisper && settings.whisperModel == entry.id
        case .language:
            if entry.builtIn {
                return settings.aiBackend == .apple
            }
            return settings.aiBackend == .ollama && settings.ollamaModel == entry.id
        }
    }

    private func isInstalled(_ entry: Entry) -> Bool {
        if entry.builtIn { return true }
        switch entry.kind {
        case .voice:
            return WhisperEngine.isInstalled(entry.id)
        case .language:
            return installedOllama?.contains(where: { $0.name == entry.id }) ?? false
        }
    }

    private func select(_ entry: Entry) {
        switch entry.kind {
        case .voice:
            if entry.builtIn {
                settings.speechEngine = .apple
            } else {
                settings.speechEngine = .whisper
                settings.whisperModel = entry.id
            }
            appState.warmUpEngine()
        case .language:
            if entry.builtIn {
                settings.aiBackend = .apple
            } else {
                settings.aiBackend = .ollama
                settings.ollamaModel = entry.id
            }
        }
    }

    private func download(_ entry: Entry) {
        guard busyModel == nil else { return }
        busyModel = entry.name
        busyLabel = "Starting…"
        busyProgress = nil
        errorMessage = nil
        Task {
            do {
                switch entry.kind {
                case .voice:
                    busyLabel = "Downloading"
                    try await WhisperEngine.downloadModel(entry.id) { fraction in
                        busyProgress = fraction
                    }
                case .language:
                    try await LocalAIService.ollamaPull(model: entry.id) { label, fraction in
                        busyLabel = label
                        busyProgress = fraction
                    }
                    await refreshOllama()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            busyModel = nil
        }
    }

    private func delete(_ entry: Entry) {
        switch entry.kind {
        case .voice:
            WhisperEngine.deleteModel(entry.id)
        case .language:
            Task {
                try? await LocalAIService.ollamaDelete(model: entry.id)
                await refreshOllama()
            }
        }
    }

    private func refreshOllama() async {
        installedOllama = await LocalAIService.ollamaModels()
        ollamaReachable = installedOllama != nil
    }
}
