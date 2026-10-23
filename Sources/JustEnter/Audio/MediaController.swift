import AppKit
import AudioToolbox
import CoreAudio

/// Quiets the room while dictating: pauses Music/Spotify if they're playing
/// (resumed afterwards) and/or ducks the system output volume.
/// All of it runs off the critical path — AppleScript and CoreAudio calls are
/// fire-and-forget on background threads so they never delay recording or
/// transcription.
@MainActor
final class MediaController {
    private var savedVolume: Float32?
    private var pausedPlayers: [String] = []
    /// Guards against begin/end overlapping when dictations are short.
    private var sequence = 0

    private let players: [(bundleID: String, appName: String)] = [
        ("com.apple.Music", "Music"),
        ("com.spotify.client", "Spotify"),
    ]

    func beginDictation(pauseMedia: Bool, duckAudio: Bool) {
        sequence += 1
        let seq = sequence

        if duckAudio {
            Task.detached(priority: .userInitiated) {
                guard let volume = Self.outputVolume(), volume > 0.05 else { return }
                await MainActor.run {
                    guard seq == self.sequence, self.savedVolume == nil else { return }
                    self.savedVolume = volume
                }
                Self.setOutputVolume(volume * 0.2)
            }
        }

        guard pauseMedia else { return }
        let running = players.filter { isRunning($0.bundleID) }.map(\.appName)
        guard !running.isEmpty else { return }
        Task {
            var paused: [String] = []
            for name in running {
                let script = """
                tell application "\(name)"
                    if player state is playing then
                        pause
                        return "paused"
                    end if
                end tell
                """
                if await Self.runScript(script) == "paused" {
                    paused.append(name)
                }
            }
            if seq == sequence {
                pausedPlayers.append(contentsOf: paused)
            } else {
                // Dictation already ended while we were pausing — undo right away.
                for name in paused {
                    _ = await Self.runScript("tell application \"\(name)\" to play")
                }
            }
        }
    }

    func endDictation() {
        sequence += 1
        if let volume = savedVolume {
            savedVolume = nil
            Task.detached(priority: .userInitiated) {
                Self.setOutputVolume(volume)
            }
        }
        let toResume = pausedPlayers
        pausedPlayers = []
        guard !toResume.isEmpty else { return }
        Task {
            for name in toResume {
                _ = await Self.runScript("tell application \"\(name)\" to play")
            }
        }
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Runs AppleScript via osascript in a subprocess on a background queue —
    /// NSAppleScript would block the main thread for hundreds of milliseconds.
    nonisolated private static func runScript(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source]
                let out = Pipe()
                process.standardOutput = out
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    // MARK: - Volume ducking (thread-safe CoreAudio calls)

    nonisolated(unsafe) private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    nonisolated private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0
        else { return nil }
        return deviceID
    }

    nonisolated private static func outputVolume() -> Float32? {
        guard let device = defaultOutputDevice() else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    nonisolated private static func setOutputVolume(_ volume: Float32) {
        guard let device = defaultOutputDevice() else { return }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr, settable.boolValue else { return }
        var value = min(max(volume, 0), 1)
        AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
}
