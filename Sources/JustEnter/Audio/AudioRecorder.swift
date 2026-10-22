import AVFoundation
import Accelerate
import Combine
import CoreAudio

/// Captures microphone audio with AVAudioEngine. Streams buffers to the active
/// transcription engine, accumulates 16 kHz mono samples for batch engines (Whisper),
/// and publishes a smoothed level for the waveform indicator.
@MainActor
final class AudioRecorder: ObservableObject {
    /// Rolling audio levels (0…1), newest last — drives the notch waveform.
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 60)
    @Published private(set) var isRunning = false

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private let engine = AVAudioEngine()
    // Created on the main actor in start(), then used only from the audio tap thread.
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private var accumulated: [Float] = []
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!

    private(set) var startedAt: Date?

    func start(deviceUID: String) throws {
        guard !isRunning else { return }
        accumulated.removeAll(keepingCapacity: true)
        levels = Array(repeating: 0, count: 60)

        if !deviceUID.isEmpty, let device = AudioDeviceManager.device(withUID: deviceUID) {
            setInputDevice(device.id)
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "JustEnter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No usable audio input — check the microphone in Settings.",
            ])
        }
        converter = AVAudioConverter(from: format, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.rmsLevel(of: buffer)
            let mono = self.convertToMono16k(buffer)
            Task { @MainActor in
                self.pushLevel(level)
                if let mono {
                    self.accumulated.append(contentsOf: mono)
                }
                self.onBuffer?(buffer)
            }
        }

        engine.prepare()
        try engine.start()
        startedAt = Date()
        isRunning = true
    }

    /// Stops the tap and returns the full recording as 16 kHz mono samples.
    func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        let samples = accumulated
        accumulated.removeAll(keepingCapacity: false)
        return samples
    }

    var duration: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    var currentFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    // MARK: - Internals

    private func setInputDevice(_ deviceID: AudioDeviceID) {
        guard let unit = engine.inputNode.audioUnit else { return }
        var device = deviceID
        AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &device, UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private func pushLevel(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    private nonisolated func convertToMono16k(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }

    private nonisolated static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        // Map roughly -50…0 dB onto 0…1 with a soft curve.
        let db = 20 * log10(max(rms, 1e-7))
        let normalized = (db + 50) / 50
        return min(max(normalized, 0), 1)
    }
}
