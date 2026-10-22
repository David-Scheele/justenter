import AVFoundation

struct TranscriptionRequest {
    /// Primary locale, used when autoDetect is off (and as fallback).
    var locale: Locale
    /// Detect the spoken language automatically (Whisper: native detection;
    /// Apple: parallel transcribers for the user's preferred languages).
    var autoDetect: Bool = false
    /// User vocabulary phrases for biasing the recognizer.
    var vocabulary: [String]
}

/// A speech-to-text backend. Streaming engines (Apple) transcribe while audio arrives;
/// batch engines (Whisper) transcribe the accumulated samples in `finish`.
@MainActor
protocol TranscriptionEngine: AnyObject {
    var kind: SpeechEngineKind { get }
    /// Emits live partial transcripts, if the engine supports streaming.
    var onPartial: ((String) -> Void)? { get set }
    /// Short human-readable progress while preparing ("Downloading 43%", "Compiling model…").
    var onStatus: ((String) -> Void)? { get set }

    /// Prepare models etc. Called once before the first session (may download models).
    func prepare(request: TranscriptionRequest) async throws
    /// Begin a live session. Buffers arrive in the microphone's native format.
    func startSession(request: TranscriptionRequest) async throws
    func feed(buffer: AVAudioPCMBuffer)
    /// End the session and return the final transcript. `samples16k` is the whole
    /// recording as 16 kHz mono Float32 for batch engines.
    func finish(samples16k: [Float]) async throws -> String
    func cancel()
}
