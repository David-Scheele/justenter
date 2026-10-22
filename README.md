# JustEnter

Speak anywhere on your Mac — AI writes it properly. A Superwhisper-style dictation app that runs **100% on-device**: local speech recognition plus Apple's local foundation model for the rewriting. No API keys, no cloud, works offline. Built native for macOS 26 (Tahoe) with Liquid Glass.

## What it does

Hold **⌥ Space** and talk (or tap to toggle). An animated island grows out of the MacBook notch showing a live waveform. Release, and your speech is transcribed on-device, rewritten by the AI according to the active mode, and pasted at your cursor.

## Features (Superwhisper parity)

- **Any microphone** — built-in, AirPods, USB interfaces; pick one in Settings → General or follow the system default.
- **Modes with prompts** — each mode bundles a Claude instruction prompt, model choice, context options, language, and paste behavior. Ships with Transcription (no AI), Message, Email, Notes, and Prompt modes; add your own.
- **Auto mode switching** — modes list the apps that activate them (bundle IDs). Focus Slack and the Message mode takes over; focus Mail and you're in Email mode.
- **Context awareness** — modes can send the active app name, your selected text (Accessibility API), and the clipboard to Claude, captured at recording start.
- **Vocabulary** — terms are fed to the speech engines as recognition hints *and* to Claude as spelling rules; separate literal replacements ("at sign" → @) run without AI.
- **Knowledge base** — snippets of standing context (projects, people, signatures) that Claude uses while rewriting.
- **Customizable shortcuts** — record & mode-cycle hotkeys are recordable in Settings. Tap = toggle, press-and-hold = push-to-talk, Esc = cancel.
- **History** — every dictation with raw transcript and final text, searchable.
- **Notch indicator** — a compact Dynamic-Island-style overlay hugging the notch: white waveform while listening, Claude-terracotta shimmer while enhancing, green check when inserted. On notch-less displays it appears as a floating island.
- **Direct insertion** — the final text is always pasted straight at the cursor of whatever input field has focus (clipboard is restored afterwards). If nothing was recognized, the app just returns to idle silently.

## Speech engines (both fully local)

| Engine | What it is | Behavior |
|---|---|---|
| **Apple Speech** (default) | macOS 26 `SpeechAnalyzer`/`SpeechTranscriber`, the new on-device model | Streams text live while you speak; zero setup |
| **Whisper** | OpenAI Whisper via WhisperKit (CoreML on the Neural Engine) — the same stack Superwhisper uses locally | Downloads the model on first use; transcribes on stop |

Whisper model options mirror Superwhisper's ladder: tiny (Fast) → base (Nano) → small (Standard) → medium (Pro) → large-v3 (Ultra / Ultra Turbo).

## The AI layer — fully local

Mode rewriting uses the **Apple Foundation Models framework** (the on-device Apple Intelligence model, macOS 26). Nothing leaves the Mac and there's nothing to configure — it just needs Apple Intelligence enabled in System Settings.

The instructions are assembled per dictation: global rules → mode instructions → vocabulary → knowledge base → context (app, selection, clipboard). The transcript goes in; only the final text comes out. If the model is unavailable (Apple Intelligence off, model still downloading), dictation keeps working — the raw transcript is inserted instead.

## Download

Grab **JustEnter.dmg** (or JustEnter.zip) from the [latest release](https://github.com/David-Scheele/justenter/releases/latest) and drag the app to Applications. On first launch macOS may warn about an unidentified developer (the app is locally signed, not notarized) — right-click → Open once.

**In-app updates:** the app checks GitHub Releases at launch; when a new version exists, "Install Update" appears in the menu bar menu and Settings → General and installs it in place with a relaunch. Cut a new release with `./release.sh <version>`.

## Build & run

Requires macOS 26+ on Apple Silicon. Only Command Line Tools needed (no Xcode):

```bash
./setup-signing.sh   # once — creates a stable signing identity so permission
                     # grants (mic, Accessibility, Keychain) survive rebuilds
./build.sh
open build/JustEnter.app
```

First run walks you through microphone + Accessibility permissions. Install with `cp -R build/JustEnter.app /Applications/`. Without the signing setup, every rebuild counts as a new app for macOS and permissions get re-asked.

Speech models are prewarmed at app launch, and any first-time download shows its progress right in the notch.

**App icon:** drop a 1024×1024 `logo.png` into `Assets/` and rebuild — `build.sh` converts it into the app icon automatically.

## Project layout

```
Sources/JustEnter/
├── App/            AppState (pipeline orchestrator), app entry + menu bar
├── Audio/          AVAudioEngine recorder, Core Audio device picker
├── Transcription/  Engine protocol, Apple SpeechAnalyzer, WhisperKit
├── AI/             Anthropic Messages API client
├── Modes/          Mode model + store (defaults included)
├── Context/        Frontmost-app watcher, selected-text/clipboard capture
├── Vocabulary/     Terms, misspellings, literal replacements
├── Knowledge/      Knowledge-base snippets
├── Hotkeys/        Carbon global hotkeys (toggle + push-to-talk)
├── Output/         Pasteboard + ⌘V synthesis with clipboard restore
├── History/        Dictation history store
└── UI/             Notch indicator, Settings tabs, History, Onboarding
```

Storage: modes/vocabulary/knowledge/history live as JSON in `~/Library/Application Support/JustEnter/`; Whisper and Ollama models are managed from Settings.

## Design

The custom surfaces (recording bubble, mode menu, onboarding) follow the native macOS design language — system materials, SF Pro text styles, system colors and accent-tinted controls — using [Alex Kässner's macOS UI Kit](https://github.com/alexkaessner/macOS-UI-Kit) as the reference: the bubble is styled like a system HUD, and the mode dropdown mirrors a native menu (material background, checkmark column, accent highlight, shortcut labels).
