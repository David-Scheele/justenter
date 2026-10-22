import Foundation
import WhisperKit

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "base"
let base = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/JustEnter/Models")

print("== fetching available models ==")
do {
    let available = try await WhisperKit.fetchAvailableModels()
    print("available: \(available)")
} catch {
    print("fetchAvailableModels ERROR: \(error)")
}

print("== downloading variant '\(variant)' ==")
do {
    let folder = try await WhisperKit.download(variant: variant, downloadBase: base, progressCallback: { p in
        print("progress: \(Int(p.fractionCompleted * 100))%")
    })
    print("downloaded to: \(folder.path)")
    print("== loading ==")
    let config = WhisperKitConfig(
        model: variant,
        downloadBase: base,
        modelFolder: folder.path,
        verbose: true,
        logLevel: .info,
        prewarm: false,
        load: true,
        download: false
    )
    let whisperKit = try await WhisperKit(config)
    print("== loaded, transcribing 1s of silence ==")
    let result = try await whisperKit.transcribe(audioArray: [Float](repeating: 0, count: 16000))
    print("OK — result: \(result.map(\.text))")
} catch {
    print("ERROR: \(error)")
}
