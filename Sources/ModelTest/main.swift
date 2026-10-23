import Foundation
import WhisperKit

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "small"
let base = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/JustEnter/Models")
let folder = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(variant)")

let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "ane"
var t0 = Date()
let compute: ModelComputeOptions? = mode == "gpu"
    ? ModelComputeOptions(audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)
    : nil
let config = WhisperKitConfig(
    model: variant, downloadBase: base, modelFolder: folder.path,
    computeOptions: compute,
    verbose: false, prewarm: mode != "noprewarm", load: true, download: false
)
let whisperKit = try await WhisperKit(config)
print(String(format: "[%@] load: %.2fs", mode, Date().timeIntervalSince(t0)))

// Simulate three dictations: ~4s of audio each (silence + faint noise).
for i in 1...3 {
    var samples = [Float](repeating: 0, count: 64_000)
    for j in 0..<samples.count { samples[j] = Float.random(in: -0.001...0.001) + (i == 1 ? 0 : 0.0001) }
    t0 = Date()
    var options = DecodingOptions()
    options.task = .transcribe
    options.language = "en"
    options.chunkingStrategy = .vad
    _ = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
    print(String(format: "transcribe #%d (4s audio): %.2fs", i, Date().timeIntervalSince(t0)))
}
