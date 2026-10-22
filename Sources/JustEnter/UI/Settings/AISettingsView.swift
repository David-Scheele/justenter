import SwiftUI
import FoundationModels

struct AISettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var appleAvailable = LocalAIService.isAvailable
    @State private var appleStatus = LocalAIService.availabilityDescription
    @State private var ollamaModels: [String]?
    @State private var checkedOllama = false

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
                        if models.isEmpty {
                            Text("No models installed yet. Pull one in a terminal, e.g. `ollama pull gpt-oss:20b` (OpenAI's open-weight model) or `ollama pull llama3.2`.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Model", selection: $settings.ollamaModel) {
                                if !models.contains(settings.ollamaModel) {
                                    Text(settings.ollamaModel).tag(settings.ollamaModel)
                                }
                                ForEach(models, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                        }
                    } else {
                        LabeledContent("Status") {
                            Label(checkedOllama ? "Not reachable on localhost:11434" : "Checking…", systemImage: "xmark.circle.fill")
                                .foregroundStyle(checkedOllama ? .orange : .secondary)
                                .font(.callout)
                        }
                        Text("Install and start Ollama (ollama.com or `brew install ollama`), then pull a model — e.g. `ollama pull gpt-oss:20b` for OpenAI's local open-weight model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Refresh") {
                        Task { await refreshOllama() }
                    }
                    .controlSize(.small)
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
}
