import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings = AppSettings.shared
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var micGranted = Permissions.microphoneGranted
    @State private var axGranted = Permissions.accessibilityGranted

    private let permissionTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Start / stop dictation") {
                    KeyRecorderView(hotkey: $settings.recordHotkey)
                }
                LabeledContent("Cycle mode") {
                    KeyRecorderView(hotkey: $settings.modeSwitchHotkey)
                }
                Text("Tap to toggle recording, press and hold to push-to-talk. Esc cancels a recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Microphone") {
                Picker("Input device", selection: $settings.inputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .onAppear { inputDevices = AudioDeviceManager.inputDevices() }
                Button("Refresh devices") {
                    inputDevices = AudioDeviceManager.inputDevices()
                }
                .controlSize(.small)
            }

            Section("Behavior") {
                Toggle("Switch modes automatically based on the active app", isOn: $settings.autoSwitchModes)
                Toggle("Play sounds", isOn: $settings.playSounds)
                Toggle("Pause music while dictating (Music, Spotify)", isOn: $settings.pauseMediaWhileDictating)
                Toggle("Duck other audio while dictating", isOn: $settings.duckAudioWhileDictating)
                Text("Paused players resume when you stop. Ducking lowers the system volume to 20% during recording and restores it afterwards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enable in
                        do {
                            if enable {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Permissions") {
                LabeledContent("Microphone") {
                    HStack {
                        permissionBadge(micGranted)
                        if !micGranted {
                            Button("Open Settings…") { Permissions.openMicrophoneSettings() }
                                .controlSize(.small)
                        }
                    }
                }
                LabeledContent("Accessibility (paste & selected text)") {
                    HStack {
                        permissionBadge(axGranted)
                        if !axGranted {
                            Button("Grant…") { Permissions.requestAccessibility() }
                                .controlSize(.small)
                            Button("Open Settings…") { Permissions.openAccessibilitySettings() }
                                .controlSize(.small)
                        }
                    }
                }
                if !axGranted {
                    Text("If JustEnter already appears in System Settings → Accessibility but pasting doesn't work, remove it there with the − button and grant it again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(permissionTimer) { _ in
            micGranted = Permissions.microphoneGranted
            axGranted = Permissions.accessibilityGranted
        }
        .onChange(of: settings.recordHotkey) { _, _ in appState.registerHotkeys() }
        .onChange(of: settings.modeSwitchHotkey) { _, _ in appState.registerHotkeys() }
    }

    @ViewBuilder
    private func permissionBadge(_ granted: Bool) -> some View {
        Label(granted ? "Granted" : "Not granted", systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(granted ? .green : .orange)
            .labelStyle(.titleAndIcon)
            .font(.callout)
    }
}
