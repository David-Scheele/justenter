import SwiftUI
import Speech

struct SpeechSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Speech engine", selection: $settings.speechEngine) {
                    ForEach(SpeechEngineKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                Text(engineHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.speechEngine == .whisper {
                Section("Whisper model") {
                    Picker("Model", selection: $settings.whisperModel) {
                        ForEach(WhisperEngine.availableModels) { model in
                            Text(model.label).tag(model.id)
                        }
                    }
                    warmupStatusRow
                    Text("Picking a model downloads and prepares it right away (CoreML, runs on the Neural Engine — fully offline). The first load of a new model takes a few minutes while macOS compiles it; after that it's instant.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Language") {
                Picker("Dictation language", selection: $settings.languageCode) {
                    Text("Automatic — detect while speaking").tag("auto")
                    Divider()
                    ForEach(languageOptions, id: \.code) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                Text("Automatic transcribes whatever language you speak (your Mac's preferred languages on the Apple engine, any language on Whisper) and the AI answers in the same language. Each mode can still pin a language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.whisperModel) { _, _ in appState.warmUpEngine() }
        .onChange(of: settings.speechEngine) { _, _ in appState.warmUpEngine() }
    }

    @ViewBuilder
    private var warmupStatusRow: some View {
        if let status = appState.modelWarmupStatus {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    if status == "Ready" {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if status.hasPrefix("Failed") {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var engineHint: String {
        switch settings.speechEngine {
        case .apple:
            return "Apple's on-device model (macOS 26 SpeechAnalyzer). Streams text live while you speak, zero setup, fully offline."
        case .whisper:
            return "OpenAI Whisper running locally via WhisperKit — the same local models Superwhisper uses. Best multilingual accuracy; transcribes when you stop."
        }
    }

    private var languageOptions: [(code: String, label: String)] {
        let codes = [
            "en-US", "en-GB", "de-DE", "fr-FR", "es-ES", "it-IT", "pt-BR",
            "nl-NL", "sv-SE", "da-DK", "nb-NO", "pl-PL", "tr-TR", "ru-RU",
            "uk-UA", "ar-SA", "he-IL", "hi-IN", "zh-CN", "zh-TW", "ja-JP", "ko-KR",
        ]
        return codes.map { code in
            let label = Locale.current.localizedString(forIdentifier: code) ?? code
            return (code: code, label: label)
        }
    }
}
