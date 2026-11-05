import Foundation
import FluidAudio
import WhisperKit

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "small"
let base = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/JustEnter/Models")

if variant == "parakeet" {
    let folder = base.appendingPathComponent("parakeet-ultra")
    var t0 = Date()
    let models = try AsrModels.loadLocal(from: folder, version: .ultra)
    let manager = AsrManager(config: .default)
    try await manager.loadModels(models)
    print(String(format: "parakeet load: %.2fs", Date().timeIntervalSince(t0)))

    for i in 1...3 {
        var samples = [Float](repeating: 0, count: 64_000)
        for j in 0..<samples.count { samples[j] = Float.random(in: -0.001...0.001) }
        t0 = Date()
        var state = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &state)
        print(String(format: "parakeet transcribe #%d (4s audio): %.2fs → \"%@\"", i, Date().timeIntervalSince(t0), result.text))
    }
    if CommandLine.arguments.count > 2 {
        let url = URL(fileURLWithPath: CommandLine.arguments[2])
        t0 = Date()
        var state = try TdtDecoderState()
        let result = try await manager.transcribe(url, decoderState: &state)
        print(String(format: "parakeet speech file: %.2fs → \"%@\"", Date().timeIntervalSince(t0), result.text))
    }
    exit(0)
}

let folder = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(variant)")
var t0 = Date()
let config = WhisperKitConfig(
    model: variant, downloadBase: base, modelFolder: folder.path,
    verbose: false, prewarm: true, load: true, download: false
)
let whisperKit = try await WhisperKit(config)
print(String(format: "whisper load: %.2fs", Date().timeIntervalSince(t0)))

for i in 1...3 {
    var samples = [Float](repeating: 0, count: 64_000)
    for j in 0..<samples.count { samples[j] = Float.random(in: -0.001...0.001) }
    t0 = Date()
    var options = DecodingOptions()
    options.task = .transcribe
    options.language = "en"
    options.chunkingStrategy = .vad
    _ = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
    print(String(format: "whisper transcribe #%d (4s audio): %.2fs", i, Date().timeIntervalSince(t0)))
}
