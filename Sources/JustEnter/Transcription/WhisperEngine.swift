import AVFoundation
import Foundation
import WhisperKit

struct WhisperModelOption: Identifiable, Hashable {
    let id: String
    let label: String
}

/// Local Whisper transcription via WhisperKit (CoreML, Apple Neural Engine) — the same
/// SDK Superwhisper uses for its local models. Batch: transcribes when recording stops.
@MainActor
final class WhisperEngine: TranscriptionEngine {
    let kind: SpeechEngineKind = .whisper
    var onPartial: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    static func modelFolder(for name: String) -> URL {
        Persistence.modelsURL.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(name)")
    }

    static func isInstalled(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: modelFolder(for: name).appendingPathComponent("AudioEncoder.mlmodelc").path)
    }

    static func deleteModel(_ name: String) {
        try? FileManager.default.removeItem(at: modelFolder(for: name))
    }

    static func downloadModel(_ name: String, progress: @escaping @MainActor (Double) -> Void) async throws {
        _ = try await WhisperKit.download(
            variant: name,
            downloadBase: Persistence.modelsURL,
            progressCallback: { p in
                let fraction = p.fractionCompleted
                Task { @MainActor in progress(fraction) }
            }
        )
    }

    static let availableModels: [WhisperModelOption] = [
        WhisperModelOption(id: "tiny", label: "Fast — tiny, ~75 MB"),
        WhisperModelOption(id: "base", label: "Nano — base, ~145 MB"),
        WhisperModelOption(id: "small", label: "Standard — small, ~480 MB"),
        WhisperModelOption(id: "medium", label: "Pro — medium, ~1.5 GB"),
        WhisperModelOption(id: "large-v3-v20240930_626MB", label: "Ultra — large-v3 compressed, ~626 MB"),
        WhisperModelOption(id: "large-v3-v20240930_turbo", label: "Ultra Turbo — large-v3 turbo, ~1.6 GB"),
    ]

    private let modelName: String
    private var whisperKit: WhisperKit?
    private var language: String?
    private var autoDetect = false
    private var vocabulary: [String] = []
    /// Single-flight loader: launch prewarm and a hotkey press must share ONE
    /// preparation — two parallel downloads/loads of the same model never settle.
    private var prepareTask: Task<Void, Error>?

    init(modelName: String) {
        self.modelName = modelName
    }

    func prepare(request: TranscriptionRequest) async throws {
        if whisperKit != nil { return }
        if prepareTask == nil {
            prepareTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.loadModel()
                } catch {
                    self.prepareTask = nil // allow a retry after a failure
                    throw error
                }
            }
        }
        try await prepareTask!.value
    }

    private func loadModel() async throws {
        let folder: URL
        let cachedFolder = Persistence.modelsURL
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelName)")
        if FileManager.default.fileExists(atPath: cachedFolder.appendingPathComponent("AudioEncoder.mlmodelc").path) {
            // Fully downloaded — no network round-trips on launch.
            folder = cachedFolder
        } else {
            onStatus?("Fetching model…")
            folder = try await WhisperKit.download(
                variant: modelName,
                downloadBase: Persistence.modelsURL,
                progressCallback: { [weak self] progress in
                    let percent = Int(progress.fractionCompleted * 100)
                    Task { @MainActor in
                        self?.onStatus?("Downloading \(percent)%")
                    }
                }
            )
        }
        onStatus?("Loading model — first time takes a while…")
        let config = WhisperKitConfig(
            model: modelName,
            downloadBase: Persistence.modelsURL,
            modelFolder: folder.path,
            verbose: false,
            prewarm: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
    }

    func startSession(request: TranscriptionRequest) async throws {
        autoDetect = request.autoDetect
        language = autoDetect ? nil : request.locale.language.languageCode?.identifier
        vocabulary = request.vocabulary
    }

    func feed(buffer: AVAudioPCMBuffer) {
        // Batch engine — audio is accumulated by the recorder.
    }

    func finish(samples16k: [Float]) async throws -> String {
        guard let whisperKit else {
            throw NSError(domain: "JustEnter.Whisper", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Whisper model isn't loaded.",
            ])
        }
        guard samples16k.count > 1600 else { return "" }

        var options = DecodingOptions()
        options.task = .transcribe
        if autoDetect {
            // Whisper's native language identification on the first audio window.
            options.detectLanguage = true
            options.usePrefillPrompt = false
        } else if let language {
            options.language = language
        }
        options.chunkingStrategy = .vad
        if !autoDetect, !vocabulary.isEmpty, let tokenizer = whisperKit.tokenizer {
            let promptText = " " + vocabulary.joined(separator: ", ")
            let tokens = tokenizer.encode(text: promptText).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            if !tokens.isEmpty {
                options.promptTokens = tokens
                options.usePrefillPrompt = true
            }
        }

        let results = try await whisperKit.transcribe(audioArray: samples16k, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        // Nothing to tear down for batch transcription.
    }
}
