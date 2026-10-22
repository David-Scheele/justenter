import SwiftUI
import FoundationModels

struct AISettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var appleAvailable = LocalAIService.isAvailable
    @State private var appleStatus = LocalAIService.availabilityDescription
    @State private var ollamaModels: [LocalAIService.OllamaModel]?
    @State private var checkedOllama = false
    @State private var installingModel: String?
    @State private var installStatus = ""
    @State private var installProgress: Double?
    @State private var installError: String?
    @State private var customModel = ""
    @State private var confirmRemove = false

    private struct CatalogEntry: Identifiable {
        let name: String
        let category: String
        let note: String
        let sizeGB: Double
        /// 1…5
        let speed: Int
        let accuracy: Int
        var id: String { name }
    }

    private static let catalog: [CatalogEntry] = [
        CatalogEntry(name: "llama3.2:1b", category: "Nano", note: "Meta — instant, basic cleanup only", sizeGB: 0.8, speed: 5, accuracy: 2),
        CatalogEntry(name: "llama3.2:3b", category: "Nano", note: "Meta — very fast, solid English", sizeGB: 2.0, speed: 5, accuracy: 3),
        CatalogEntry(name: "qwen3:4b", category: "Small", note: "Alibaba — fast, good multilingual", sizeGB: 2.6, speed: 4, accuracy: 3),
        CatalogEntry(name: "gemma3:4b", category: "Small", note: "Google — strong German + English, recommended", sizeGB: 3.3, speed: 4, accuracy: 4),
        CatalogEntry(name: "qwen3:8b", category: "Medium", note: "Alibaba — noticeably better writing", sizeGB: 5.2, speed: 3, accuracy: 4),
        CatalogEntry(name: "gemma3:12b", category: "Medium", note: "Google — best quality that fits 18 GB comfortably", sizeGB: 8.1, speed: 2, accuracy: 5),
        CatalogEntry(name: "deepseek-r1:8b", category: "Research", note: "DeepSeek — reasoning model, slower responses", sizeGB: 5.2, speed: 2, accuracy: 4),
        CatalogEntry(name: "gpt-oss:20b", category: "Large · Research", note: "OpenAI open-weight reasoning — heavy on 18 GB RAM", sizeGB: 13.0, speed: 1, accuracy: 5),
    ]

    private let refreshTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Local AI backend") {
                Picker("Backend", selection: $settings.aiBackend) {
                    ForEach(AIBackend.allCases) { backend in
                        Text(backend.label).tag(backend)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Text("Everything runs on this Mac — no API keys, no cloud, works offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.aiBackend == .apple {
                Section("Apple Intelligence") {
                    LabeledContent("Status") {
                        Label(appleStatus, systemImage: appleAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(appleAvailable ? .green : .orange)
                            .font(.callout)
                    }
                    if !appleAvailable {
                        Button("Open Apple Intelligence Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            } else {
                Section("Ollama") {
                    if let models = ollamaModels {
                        LabeledContent("Status") {
                            Label("Running — \(models.count) model\(models.count == 1 ? "" : "s") installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                        }
                        if !models.isEmpty {
                            Picker("Active model", selection: $settings.ollamaModel) {
                                if !models.contains(where: { $0.name == settings.ollamaModel }) {
                                    Text(settings.ollamaModel).tag(settings.ollamaModel)
                                }
                                ForEach(models) { model in
                                    Text(model.label).tag(model.name)
                                }
                            }
                            Button("Remove \(settings.ollamaModel)…", role: .destructive) {
                                confirmRemove = true
                            }
                            .controlSize(.small)
                            .confirmationDialog(
                                "Remove \(settings.ollamaModel) from disk?",
                                isPresented: $confirmRemove
                            ) {
                                Button("Remove", role: .destructive) {
                                    Task {
                                        try? await LocalAIService.ollamaDelete(model: settings.ollamaModel)
                                        await refreshOllama()
                                        if let first = ollamaModels?.first {
                                            settings.ollamaModel = first.name
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        LabeledContent("Status") {
                            Label(checkedOllama ? "Not reachable on localhost:11434" : "Checking…", systemImage: "xmark.circle.fill")
                                .foregroundStyle(checkedOllama ? .orange : .secondary)
                                .font(.callout)
                        }
                        Text("Install and start Ollama first: `brew install ollama && brew services start ollama` — then install models right here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Refresh") {
                        Task { await refreshOllama() }
                    }
                    .controlSize(.small)
                }

                if ollamaModels != nil {
                    Section("Install models") {
                        if let installingModel {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    if let installProgress {
                                        ProgressView(value: installProgress)
                                    } else {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                Text("\(installingModel): \(installStatus)\(installProgress.map { " — \(Int($0 * 100))%" } ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(Self.catalog) { entry in
                            catalogRow(entry)
                        }
                        HStack {
                            TextField("Any other Ollama model, e.g. mistral:7b", text: $customModel)
                                .textFieldStyle(.roundedBorder)
                            Button("Install") {
                                install(customModel.trimmingCharacters(in: .whitespaces))
                            }
                            .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty || installingModel != nil)
                        }
                        if let installError {
                            Text(installError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("Tone") {
                Slider(value: $settings.formality, in: 0...1) {
                    Text("Tone")
                } minimumValueLabel: {
                    Text("Casual")
                } maximumValueLabel: {
                    Text("Formal")
                }
                Text("Currently: \(LocalAIService.toneDescription(for: settings.formality))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Filler words (um, ähm, äh…) and self-corrections (“at twelve — ähm no, at 1” → “at 1”) are always removed, in every mode, regardless of this slider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Fallback") {
                Text("If the selected backend is unavailable, dictation still works — the raw transcript is cleaned deterministically and inserted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await refreshOllama() }
        .onChange(of: settings.aiBackend) { _, backend in
            if backend == .ollama {
                Task { await refreshOllama() }
            }
        }
        .onReceive(refreshTimer) { _ in
            appleAvailable = LocalAIService.isAvailable
            appleStatus = LocalAIService.availabilityDescription
        }
    }

    private func refreshOllama() async {
        ollamaModels = await LocalAIService.ollamaModels()
        checkedOllama = true
    }

    @ViewBuilder
    private func catalogRow(_ entry: CatalogEntry) -> some View {
        let isInstalled = ollamaModels?.contains(where: { $0.name == entry.name }) ?? false
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text(entry.category)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Text(entry.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    rating("Speed", entry.speed)
                    rating("Accuracy", entry.accuracy)
                    Text(String(format: "%.1f GB", entry.sizeGB))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isInstalled {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Button("Install") {
                    install(entry.name)
                }
                .controlSize(.small)
                .disabled(installingModel != nil)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rating(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index < value ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private func install(_ name: String) {
        guard installingModel == nil, !name.isEmpty else { return }
        installingModel = name
        installError = nil
        installProgress = nil
        installStatus = "Starting…"
        Task {
            do {
                try await LocalAIService.ollamaPull(model: name) { status, fraction in
                    installStatus = status
                    installProgress = fraction
                }
                installingModel = nil
                customModel = ""
                await refreshOllama()
                settings.ollamaModel = name
            } catch {
                installError = error.localizedDescription
                installingModel = nil
            }
        }
    }
}
