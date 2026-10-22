import AppKit
import AudioToolbox
import CoreAudio

/// Quiets the room while dictating: pauses Music/Spotify if they're playing
/// (resumed afterwards) and/or ducks the system output volume.
@MainActor
final class MediaController {
    private var savedVolume: Float32?
    private var pausedPlayers: [String] = []

    private let players: [(bundleID: String, appName: String)] = [
        ("com.apple.Music", "Music"),
        ("com.spotify.client", "Spotify"),
    ]

    func beginDictation(pauseMedia: Bool, duckAudio: Bool) {
        if pauseMedia {
            pausePlayers()
        }
        if duckAudio {
            duckVolume()
        }
    }

    func endDictation() {
        restoreVolume()
        resumePlayers()
    }

    // MARK: - Music players (AppleScript, idempotent, only resumed if we paused them)

    private func pausePlayers() {
        pausedPlayers = []
        for player in players where isRunning(player.bundleID) {
            let script = """
            tell application "\(player.appName)"
                if player state is playing then
                    pause
                    return "paused"
                end if
            end tell
            """
            if runAppleScript(script) == "paused" {
                pausedPlayers.append(player.appName)
            }
        }
    }

    private func resumePlayers() {
        for name in pausedPlayers {
            _ = runAppleScript("tell application \"\(name)\" to play")
        }
        pausedPlayers = []
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result.stringValue
    }

    // MARK: - Volume ducking (everything else: browsers, videos, …)

    private func duckVolume() {
        guard savedVolume == nil, let volume = Self.outputVolume(), volume > 0.05 else { return }
        savedVolume = volume
        Self.setOutputVolume(volume * 0.2)
    }

    private func restoreVolume() {
        if let volume = savedVolume {
            Self.setOutputVolume(volume)
            savedVolume = nil
        }
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func defaultOutputDevice() -> AudioDeviceID? {
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

    private static func outputVolume() -> Float32? {
        guard let device = defaultOutputDevice() else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    private static func setOutputVolume(_ volume: Float32) {
        guard let device = defaultOutputDevice() else { return }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr, settable.boolValue else { return }
        var value = min(max(volume, 0), 1)
        AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
}
