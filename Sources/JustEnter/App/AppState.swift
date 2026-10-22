import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import SwiftUI

enum DictationPhase: Equatable {
    case idle
    case preparing
    case recording
    case transcribing
    case enhancing
    case done
    case error(String)
}

/// Central coordinator: hotkeys → recording → transcription → Claude → paste.
@MainActor
final class AppState: ObservableObject {
    @Published var phase: DictationPhase = .idle
    /// Mode symbol briefly shown in the menu bar after a mode switch.
    @Published var menuBarModeSymbol: String?
    /// The mode dropdown attached below the bubble.
    @Published var modeDropdownVisible = false
    /// Progress shown in the notch while a speech model loads ("Downloading 43%").
    @Published var preparingStatus = "Loading model…"
    /// Model download/compile progress surfaced in Settings → Speech.
    @Published var modelWarmupStatus: String?

    let settings = AppSettings.shared
    let modesStore = ModesStore()
    let vocabulary = VocabularyStore()
    let knowledge = KnowledgeStore()
    let history = HistoryStore()
    let recorder = AudioRecorder()
    let appWatcher = AppWatcher()
    let hotkeys = HotkeyManager()

    private let ai = LocalAIService()
    private let media = MediaController()
    private var bubble: BubbleController?
    private var soundCache: [String: NSSound] = [:]
    private var dropdownGeneration = 0
    private var engines: [String: TranscriptionEngine] = [:]
    private var activeEngine: TranscriptionEngine?
    private var pressBeganAt: Date?
    private var capturedContext = DictationContext()
    private var recordingMode: Mode?
    private var generation = 0
    private var flashGeneration = 0
    /// Bumped on every start/cancel; in-flight pipeline results are dropped when stale.
    private var pipelineID = 0

    var recordingStartedAt: Date? { recorder.startedAt }
    var activeModeName: String { modesStore.activeMode.name }
    var activeModeSymbol: String { modesStore.activeMode.symbol }

    // MARK: - Lifecycle

    func start() {
        bubble = BubbleController(appState: self)

        hotkeys.onPress = { [weak self] action in self?.handlePress(action) }
        hotkeys.onRelease = { [weak self] action in self?.handleRelease(action) }
        hotkeys.start()
        registerHotkeys()

        appWatcher.onChange = { [weak self] bundleID, _ in
            self?.autoSwitchMode(for: bundleID)
        }
        appWatcher.start()

        // Prewarm the speech model in the background so the first dictation
        // doesn't sit in "Loading model…".
        warmUpEngine()

        // Quiet update check at launch; result shows in Settings and the menu.
        Task {
            await UpdateChecker.shared.check()
        }
    }

    /// Downloads/loads the currently selected speech model in the background.
    /// Called at launch and whenever the engine or model changes in Settings.
    func warmUpEngine() {
        let engine = engineForCurrentSettings()
        engine.onStatus = { [weak self] status in
            self?.modelWarmupStatus = status
        }
        modelWarmupStatus = "Preparing…"
        Task {
            do {
                try await engine.prepare(request: makeTranscriptionRequest(for: nil))
                modelWarmupStatus = "Ready"
            } catch {
                modelWarmupStatus = "Failed — \(error.localizedDescription)"
            }
        }
    }

    /// "auto" (the default) detects the spoken language; anything else pins it.
    private func makeTranscriptionRequest(for mode: Mode?) -> TranscriptionRequest {
        var setting = settings.languageCode
        if let mode, !mode.language.isEmpty {
            setting = mode.language
        }
        let auto = setting.lowercased() == "auto"
        return TranscriptionRequest(
            locale: Locale(identifier: auto ? (Locale.preferredLanguages.first ?? "en-US") : setting),
            autoDetect: auto,
            vocabulary: (mode?.useVocabulary ?? true) ? vocabulary.phrases : []
        )
    }

    func registerHotkeys() {
        hotkeys.register(settings.recordHotkey, for: .record)
        hotkeys.register(settings.modeSwitchHotkey, for: .modeSwitch)
    }

    // MARK: - Hotkey handling (tap = toggle, hold = push-to-talk)

    private func handlePress(_ action: HotkeyManager.Action) {
        if let digitIndex = action.digitIndex {
            selectMode(at: digitIndex)
            return
        }
        switch action {
        case .record:
            pressBeganAt = Date()
            if phase == .idle {
                Task { await startRecording() }
            } else if phase == .recording {
                Task { await stopAndProcess() }
            }
        case .modeSwitch:
            cycleMode()
        case .cancel:
            if modeDropdownVisible {
                closeModeDropdown()
            } else {
                cancelDictation()
            }
        default:
            break
        }
    }

    private func handleRelease(_ action: HotkeyManager.Action) {
        guard action == .record, phase == .recording else { return }
        if let began = pressBeganAt, Date().timeIntervalSince(began) > 0.6 {
            // Held long enough to count as push-to-talk: stop on release.
            Task { await stopAndProcess() }
        }
    }

    // MARK: - Mode switching

    private func autoSwitchMode(for bundleID: String) {
        guard settings.autoSwitchModes, phase == .idle else { return }
        // The Auto mode resolves the app itself per dictation — don't switch away from it.
        guard !modesStore.activeMode.isAuto else { return }
        guard let mode = modesStore.mode(for: bundleID), mode.id != modesStore.activeModeID else { return }
        modesStore.select(mode)
        flashMode(mode)
    }

    /// Resolution for the Auto mode: an app-matched mode wins; otherwise the local
    /// AI routes by content; otherwise plain cleanup.
    private func resolveAutoMode(transcript: String) async -> Mode {
        let candidates = modesStore.modes.filter { !$0.isAuto }
        if let bundleID = capturedContext.appBundleID,
           let match = candidates.first(where: { $0.activationBundleIDs.contains(bundleID) }) {
            return match
        }
        if let name = await ai.classifyMode(
            transcript: transcript,
            appName: capturedContext.appName,
            candidates: candidates.map { (name: $0.name, details: $0.details.isEmpty ? $0.name : $0.details) }
        ), let match = candidates.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        return Mode(name: "Cleanup", aiEnabled: false)
    }

    /// Mode hotkey: first press opens the dropdown under the bubble, further
    /// presses cycle through the modes. Digits 1–9 or a click select directly;
    /// it closes by itself shortly after the last input.
    func cycleMode() {
        if modeDropdownVisible {
            let modes = modesStore.modes
            guard !modes.isEmpty else { return }
            let currentIndex = modes.firstIndex(where: { $0.id == modesStore.activeModeID }) ?? 0
            let next = modes[(currentIndex + 1) % modes.count]
            modesStore.select(next, manual: true)
            flashMode(next)
        } else {
            openModeDropdown()
        }
        restartDropdownTimer()
    }

    private func openModeDropdown() {
        modeDropdownVisible = true
        bubble?.show()
        bubble?.setInteractive(true)
        for (index, digit) in HotkeyManager.Action.digits.enumerated() where index < modesStore.modes.count {
            hotkeys.register(Hotkey(keyCode: Self.digitKeyCodes[index], carbonModifiers: 0), for: digit)
        }
        hotkeys.register(Hotkey(keyCode: UInt32(kVK_Escape), carbonModifiers: 0), for: .cancel)
    }

    func closeModeDropdown() {
        guard modeDropdownVisible else { return }
        modeDropdownVisible = false
        dropdownGeneration += 1
        bubble?.setInteractive(false)
        for digit in HotkeyManager.Action.digits {
            hotkeys.unregister(digit)
        }
        if !isDictating {
            hotkeys.unregister(.cancel)
            if phase == .idle {
                bubble?.hide()
            }
        }
    }

    func selectModeFromDropdown(_ mode: Mode) {
        modesStore.select(mode, manual: true)
        flashMode(mode)
        closeModeDropdown()
    }

    private func selectMode(at index: Int) {
        guard modeDropdownVisible, modesStore.modes.indices.contains(index) else { return }
        selectModeFromDropdown(modesStore.modes[index])
    }

    private func restartDropdownTimer() {
        dropdownGeneration += 1
        let gen = dropdownGeneration
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard gen == dropdownGeneration else { return }
            closeModeDropdown()
        }
    }

    private static let digitKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
    ]

    /// Mode switches don't open the notch — the menu bar icon briefly becomes
    /// the new mode's symbol instead.
    private func flashMode(_ mode: Mode) {
        flashGeneration += 1
        let gen = flashGeneration
        menuBarModeSymbol = mode.symbol
        Task {
            try? await Task.sleep(for: .seconds(6))
            guard gen == flashGeneration else { return }
            menuBarModeSymbol = nil
        }
    }

    // MARK: - Recording pipeline

    func toggleRecording() {
        if phase == .idle {
            Task { await startRecording() }
        } else if phase == .recording {
            Task { await stopAndProcess() }
        }
    }

    var isDictating: Bool {
        switch phase {
        case .preparing, .recording, .transcribing, .enhancing: return true
        default: return false
        }
    }

    func startRecording() async {
        guard phase == .idle else { return }
        closeModeDropdown()
        generation += 1
        pipelineID += 1

        guard await Permissions.requestMicrophone() else {
            showError("Microphone access denied — enable it in System Settings.")
            Permissions.openMicrophoneSettings()
            return
        }

        let mode = modesStore.activeMode
        recordingMode = mode

        // Context is captured at recording start, like Superwhisper.
        capturedContext = DictationContext(
            appName: appWatcher.frontmostName,
            appBundleID: appWatcher.frontmostBundleID,
            selectedText: mode.includeSelectedText ? ContextCapture.selectedText() : nil,
            clipboardText: mode.includeClipboard ? ContextCapture.clipboardText() : nil
        )

        let request = makeTranscriptionRequest(for: mode)

        preparingStatus = "Loading model…"
        phase = .preparing
        bubble?.show()
        // Esc cancels from this point until the text is inserted (or an error shows).
        hotkeys.register(Hotkey(keyCode: UInt32(kVK_Escape), carbonModifiers: 0), for: .cancel)
        let pid = pipelineID
        do {
            let engine = engineForCurrentSettings()
            activeEngine = engine
            engine.onStatus = { [weak self] status in
                self?.preparingStatus = status
            }
            try await engine.prepare(request: request)
            guard pid == pipelineID else { return }
            try await engine.startSession(request: request)
            guard pid == pipelineID else { return }
            recorder.onBuffer = { [weak engine] buffer in
                engine?.feed(buffer: buffer)
            }
            try recorder.start(deviceUID: settings.inputDeviceUID)
        } catch {
            guard pid == pipelineID else { return }
            showError(error.localizedDescription)
            return
        }

        media.beginDictation(
            pauseMedia: settings.pauseMediaWhileDictating,
            duckAudio: settings.duckAudioWhileDictating
        )
        phase = .recording
        playSound("whisper-start")
    }

    func stopAndProcess() async {
        guard phase == .recording, let mode = recordingMode else { return }
        let pid = pipelineID
        let samples = recorder.stop()
        recorder.onBuffer = nil
        media.endDictation()
        let duration = recorder.duration
        phase = .transcribing

        do {
            guard let engine = activeEngine else { throw simpleError("No speech engine active.") }
            var transcript = try await engine.finish(samples16k: samples)
            guard pid == pipelineID else { return }
            transcript = vocabulary.apply(to: transcript).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                // Nothing recognizable — return to idle quietly, no error state.
                hotkeys.unregister(.cancel)
                phase = .idle
                bubble?.hide()
                return
            }

            // Every dictation gets an AI pass: full mode styling when the mode has AI
            // enabled, otherwise a strict cleanup (fillers, self-corrections, punctuation).
            phase = .enhancing

            // Auto mode: resolve the real mode now — by target app, then by content.
            var effectiveMode = mode
            var modeLabel = mode.name
            if mode.isAuto {
                effectiveMode = await resolveAutoMode(transcript: transcript)
                modeLabel = "Auto → \(effectiveMode.name)"
                guard pid == pipelineID else { return }
            }

            var finalText: String
            var aiUnavailableNotice: String?
            do {
                finalText = try await ai.enhance(
                    transcript: transcript,
                    mode: effectiveMode,
                    formality: settings.formality,
                    vocabularySection: vocabulary.promptSection,
                    knowledgeSection: knowledge.promptSection,
                    context: capturedContext
                )
                finalText = vocabulary.apply(to: finalText)
            } catch {
                // Local model unavailable or refused — strip fillers deterministically.
                finalText = TranscriptCleaner.strip(transcript)
                if let aiError = error as? LocalAIError, aiError.isUnavailable {
                    aiUnavailableNotice = "Inserted raw — \(aiError.localizedDescription)"
                }
            }
            guard pid == pipelineID else { return }

            hotkeys.unregister(.cancel)
            TextInserter.insert(finalText, restoreClipboard: effectiveMode.restoreClipboard)
            history.add(HistoryRecord(
                date: Date(),
                modeName: modeLabel,
                appName: capturedContext.appName ?? "—",
                duration: duration,
                rawTranscript: transcript,
                finalText: finalText
            ))

            if !Permissions.accessibilityGranted {
                // Text is on the clipboard but couldn't be pasted.
                phase = .error("Copied — grant Accessibility to auto-paste")
                scheduleReturnToIdle(after: 3.0)
            } else if let aiUnavailableNotice {
                phase = .error(aiUnavailableNotice)
                scheduleReturnToIdle(after: 2.5)
            } else {
                phase = .done
                playSound("whisper-done")
                scheduleReturnToIdle(after: 1.1)
            }
        } catch {
            guard pid == pipelineID else { return }
            showError(error.localizedDescription)
        }
    }

    /// Cancels wherever the pipeline currently is — recording, transcribing or writing.
    func cancelDictation() {
        guard isDictating else { return }
        pipelineID += 1
        hotkeys.unregister(.cancel)
        if recorder.isRunning {
            _ = recorder.stop()
        }
        recorder.onBuffer = nil
        media.endDictation()
        activeEngine?.cancel()
        phase = .idle
        bubble?.hide()
    }

    // MARK: - Helpers

    private func engineForCurrentSettings() -> TranscriptionEngine {
        let kind = settings.speechEngine
        let key = kind == .whisper ? "whisper-\(settings.whisperModel)" : kind.rawValue
        // Whisper models are heavy; keep only the selected one in memory.
        if kind == .whisper, phase == .idle {
            engines = engines.filter { $0.key == key || !$0.key.hasPrefix("whisper-") }
        }
        if let existing = engines[key] { return existing }
        let engine: TranscriptionEngine
        switch kind {
        case .apple:
            engine = AppleSpeechEngine()
        case .whisper:
            engine = WhisperEngine(modelName: settings.whisperModel)
        }
        engines[key] = engine
        return engine
    }

    private func showError(_ message: String) {
        hotkeys.unregister(.cancel)
        media.endDictation()
        phase = .error(message)
        bubble?.show()
        playSound("whisper-error")
        scheduleReturnToIdle(after: 3.0)
    }

    private func scheduleReturnToIdle(after seconds: Double) {
        generation += 1
        let gen = generation
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard gen == generation else { return }
            if phase != .recording {
                phase = .idle
                bubble?.hide()
            }
        }
    }

    /// Soft generated "whisper" sounds bundled in Resources (whisper-start/-done/-error).
    private func playSound(_ name: String) {
        guard settings.playSounds else { return }
        if let cached = soundCache[name] {
            cached.stop()
            cached.play()
            return
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: true)
        else { return }
        soundCache[name] = sound
        sound.play()
    }

    private func simpleError(_ message: String) -> NSError {
        NSError(domain: "JustEnter", code: 10, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
