import Foundation
import Combine

enum AIBackend: String, CaseIterable, Identifiable {
    case apple
    case ollama

    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple Intelligence — built-in, zero setup"
        case .ollama: return "Ollama — local models (GPT-OSS, Llama, Qwen…)"
        }
    }
}

enum SpeechEngineKind: String, Codable, CaseIterable, Identifiable {
    case apple
    case whisper

    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple Speech (on-device)"
        case .whisper: return "Whisper (local model)"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var speechEngine: SpeechEngineKind {
        didSet { defaults.set(speechEngine.rawValue, forKey: "speechEngine") }
    }
    @Published var whisperModel: String {
        didSet { defaults.set(whisperModel, forKey: "whisperModel") }
    }
    @Published var languageCode: String {
        didSet { defaults.set(languageCode, forKey: "languageCode") }
    }
    @Published var inputDeviceUID: String {
        didSet { defaults.set(inputDeviceUID, forKey: "inputDeviceUID") }
    }
    @Published var autoSwitchModes: Bool {
        didSet { defaults.set(autoSwitchModes, forKey: "autoSwitchModes") }
    }
    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: "playSounds") }
    }
    /// Global writing tone, 0 = casual … 1 = formal.
    @Published var formality: Double {
        didSet { defaults.set(formality, forKey: "formality") }
    }
    /// Fine-grained GitHub token (read-only) for update checks — the repo is private.
    @Published var githubToken: String {
        didSet { Keychain.set(githubToken, for: "github-token") }
    }
    @Published var aiBackend: AIBackend {
        didSet { defaults.set(aiBackend.rawValue, forKey: "aiBackend") }
    }
    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: "ollamaModel") }
    }
    @Published var pauseMediaWhileDictating: Bool {
        didSet { defaults.set(pauseMediaWhileDictating, forKey: "pauseMediaWhileDictating") }
    }
    @Published var duckAudioWhileDictating: Bool {
        didSet { defaults.set(duckAudioWhileDictating, forKey: "duckAudioWhileDictating") }
    }
    /// Recording hotkey stored as "keyCode,modifierFlags" (Carbon values).
    @Published var recordHotkey: Hotkey {
        didSet { defaults.set(recordHotkey.stringValue, forKey: "recordHotkey") }
    }
    @Published var modeSwitchHotkey: Hotkey {
        didSet { defaults.set(modeSwitchHotkey.stringValue, forKey: "modeSwitchHotkey") }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    private let defaults = UserDefaults.standard

    private init() {
        speechEngine = SpeechEngineKind(rawValue: defaults.string(forKey: "speechEngine") ?? "") ?? .apple
        whisperModel = defaults.string(forKey: "whisperModel") ?? "base"
        languageCode = defaults.string(forKey: "languageCode") ?? "auto"
        inputDeviceUID = defaults.string(forKey: "inputDeviceUID") ?? ""
        autoSwitchModes = defaults.object(forKey: "autoSwitchModes") as? Bool ?? true
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        formality = defaults.object(forKey: "formality") as? Double ?? 0.5
        githubToken = Keychain.get("github-token") ?? ""
        aiBackend = AIBackend(rawValue: defaults.string(forKey: "aiBackend") ?? "") ?? .apple
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? "gpt-oss:20b"
        pauseMediaWhileDictating = defaults.object(forKey: "pauseMediaWhileDictating") as? Bool ?? true
        duckAudioWhileDictating = defaults.object(forKey: "duckAudioWhileDictating") as? Bool ?? false
        recordHotkey = Hotkey(stringValue: defaults.string(forKey: "recordHotkey")) ?? Hotkey.defaultRecord
        modeSwitchHotkey = Hotkey(stringValue: defaults.string(forKey: "modeSwitchHotkey")) ?? Hotkey.defaultModeSwitch
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
    }
}
