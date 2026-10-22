import SwiftUI
import ServiceManagement

/// Configuration, Superwhisper-style: keyboard shortcuts, behavior, microphone,
/// permissions — card rows with reset buttons.
struct ConfigurationPane: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings = AppSettings.shared
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var micGranted = Permissions.microphoneGranted
    @State private var axGranted = Permissions.accessibilityGranted

    private let permissionTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        PaneScaffold(title: "Configuration") {
            PaneSectionTitle("Keyboard Shortcuts")
            SettingsCard {
                CardRow(title: "Toggle Recording", subtitle: "Tap to start and stop, hold for push-to-talk") {
                    HStack(spacing: 6) {
                        resetButton(isDefault: settings.recordHotkey == .defaultRecord) {
                            settings.recordHotkey = .defaultRecord
                        }
                        KeyRecorderView(hotkey: $settings.recordHotkey)
                    }
                }
                CardDivider()
                CardRow(title: "Change Mode", subtitle: "Opens the mode switcher, tap again to cycle") {
                    HStack(spacing: 6) {
                        resetButton(isDefault: settings.modeSwitchHotkey == .defaultModeSwitch) {
                            settings.modeSwitchHotkey = .defaultModeSwitch
                        }
                        KeyRecorderView(hotkey: $settings.modeSwitchHotkey)
                    }
                }
                CardDivider()
                CardRow(title: "Cancel Recording", subtitle: "Discards the active dictation") {
                    Text("esc")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                }
            }

            PaneSectionTitle("Behavior")
            SettingsCard {
                CardRow(title: "Switch modes automatically", subtitle: "Based on the active app") {
                    Toggle("", isOn: $settings.autoSwitchModes).labelsHidden().toggleStyle(.switch)
                }
                CardDivider()
                CardRow(title: "Launch at login") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
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
                CardDivider()
                CardRow(title: "Language") {
                    Picker("", selection: $settings.languageCode) {
                        Text("Automatic — detect while speaking").tag("auto")
                        Divider()
                        ForEach(languageOptions, id: \.code) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                }
                CardDivider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tone")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(LocalAIService.toneDescription(for: settings.formality))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.formality, in: 0...1) {
                        Text("Tone")
                    } minimumValueLabel: {
                        Text("Casual").font(.system(size: 10))
                    } maximumValueLabel: {
                        Text("Formal").font(.system(size: 10))
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }

            PaneSectionTitle("Microphone")
            SettingsCard {
                CardRow(title: "Input device") {
                    Picker("", selection: $settings.inputDeviceUID) {
                        Text("System default").tag("")
                        ForEach(inputDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                    .onAppear { inputDevices = AudioDeviceManager.inputDevices() }
                }
                CardDivider()
                CardRow(title: "Refresh devices") {
                    Button("Refresh") { inputDevices = AudioDeviceManager.inputDevices() }
                        .controlSize(.small)
                }
            }

            PaneSectionTitle("Permissions")
            SettingsCard {
                CardRow(title: "Microphone") {
                    permissionBadge(micGranted) { Permissions.openMicrophoneSettings() }
                }
                CardDivider()
                CardRow(title: "Accessibility", subtitle: "Pasting at the cursor and reading the selection") {
                    HStack(spacing: 8) {
                        if !axGranted {
                            Button("Grant…") { Permissions.requestAccessibility() }
                                .controlSize(.small)
                        }
                        permissionBadge(axGranted) { Permissions.openAccessibilitySettings() }
                    }
                }
            }

            PaneSectionTitle("Updates")
            SettingsCard {
                CardRow(title: "GitHub token", subtitle: "Optional — avoids API rate limits, stored in the Keychain") {
                    SecureField("ghp_…", text: $settings.githubToken)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 220)
                }
            }
        }
        .onReceive(permissionTimer) { _ in
            micGranted = Permissions.microphoneGranted
            axGranted = Permissions.accessibilityGranted
        }
        .onChange(of: settings.recordHotkey) { _, _ in appState.registerHotkeys() }
        .onChange(of: settings.modeSwitchHotkey) { _, _ in appState.registerHotkeys() }
    }

    @ViewBuilder
    private func resetButton(isDefault: Bool, action: @escaping () -> Void) -> some View {
        if !isDefault {
            Button(action: action) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reset to default")
        }
    }

    @ViewBuilder
    private func permissionBadge(_ granted: Bool, openSettings: @escaping () -> Void) -> some View {
        if granted {
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))
        } else {
            Button {
                openSettings()
            } label: {
                Label("Not granted", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private var languageOptions: [(code: String, label: String)] {
        let codes = [
            "en-US", "en-GB", "de-DE", "fr-FR", "es-ES", "it-IT", "pt-BR",
            "nl-NL", "sv-SE", "da-DK", "nb-NO", "pl-PL", "tr-TR", "ru-RU",
            "uk-UA", "ar-SA", "he-IL", "hi-IN", "zh-CN", "zh-TW", "ja-JP", "ko-KR",
        ]
        return codes.map { code in
            (code: code, label: Locale.current.localizedString(forIdentifier: code) ?? code)
        }
    }
}

/// Sound pane: effects on/off and what happens to other audio while recording.
struct SoundPane: View {
    @ObservedObject private var settings = AppSettings.shared

    private var recordingBehavior: Binding<String> {
        Binding(
            get: {
                switch (settings.pauseMediaWhileDictating, settings.duckAudioWhileDictating) {
                case (true, true): return "both"
                case (true, false): return "pause"
                case (false, true): return "duck"
                case (false, false): return "nothing"
                }
            },
            set: { value in
                settings.pauseMediaWhileDictating = (value == "pause" || value == "both")
                settings.duckAudioWhileDictating = (value == "duck" || value == "both")
            }
        )
    }

    var body: some View {
        PaneScaffold(title: "Sound") {
            SettingsCard {
                CardRow(title: "Sound effects", subtitle: "Subtle ticks on start, insert and errors") {
                    Picker("", selection: $settings.playSounds) {
                        Text("Simple").tag(true)
                        Text("Off").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            PaneSectionTitle("Recording")
            SettingsCard {
                CardRow(title: "Sound while recording", subtitle: "What happens to music and other audio") {
                    Picker("", selection: recordingBehavior) {
                        Text("Nothing").tag("nothing")
                        Text("Pause music").tag("pause")
                        Text("Duck other audio").tag("duck")
                        Text("Pause & duck").tag("both")
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            Text("“Pause music” pauses Music or Spotify if they're playing and resumes them afterwards. “Duck” lowers the system volume to 20% during recording.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
