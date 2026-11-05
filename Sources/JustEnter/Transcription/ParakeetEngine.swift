import AVFoundation
import FluidAudio
import Foundation

extension AsrManager {
    /// Runs one transcription with fresh decoder state inside the actor —
    /// the stateful API's `inout` parameter can't cross the actor boundary.
    func transcribeOnce(_ samples: [Float]) async throws -> ASRResult {
        var state = try TdtDecoderState()
        return try await transcribe(samples, decoderState: &state)
    }
}

/// NVIDIA Parakeet (TDT "ultra", multilingual) via FluidAudio — the same Parakeet
/// family Superwhisper ships. Batch engine: transcribes when recording stops,
/// typically much faster than Whisper at comparable accuracy.
@MainActor
final class ParakeetEngine: TranscriptionEngine {
    let kind: SpeechEngineKind = .parakeet
    var onPartial: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private var manager: AsrManager?
    private var prepareTask: Task<Void, Error>?

    static var modelFolder: URL {
        Persistence.modelsURL.appendingPathComponent("parakeet-ultra")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent("Encoder.mlmodelc").path)
    }

    static func deleteModel() {
        try? FileManager.default.removeItem(at: modelFolder)
    }

    func prepare(request: TranscriptionRequest) async throws {
        if manager != nil { return }
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
        guard Self.isInstalled else {
            throw NSError(domain: "JustEnter.Parakeet", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Parakeet model not found in Application Support/JustEnter/Models/parakeet-ultra.",
            ])
        }
        onStatus?("Loading Parakeet…")
        let folder = Self.modelFolder
        let models = try await Task.detached(priority: .userInitiated) {
            try AsrModels.loadLocal(from: folder, version: .ultra)
        }.value
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)

        // Warm the full decode path so the first dictation is as fast as the rest.
        onStatus?("Warming up…")
        _ = try? await manager.transcribeOnce([Float](repeating: 0, count: 16_000))
        self.manager = manager
        onStatus?("Ready")
    }

    func startSession(request: TranscriptionRequest) async throws {
        // Batch engine, multilingual by nature — nothing to configure per session.
    }

    func feed(buffer: AVAudioPCMBuffer) {
        // Batch engine — audio is accumulated by the recorder.
    }

    func finish(samples16k: [Float]) async throws -> String {
        guard let manager else {
            throw NSError(domain: "JustEnter.Parakeet", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Parakeet model isn't loaded.",
            ])
        }
        guard samples16k.count > 1600 else { return "" }
        let result = try await manager.transcribeOnce(samples16k)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        // Nothing to tear down for batch transcription.
    }
}
