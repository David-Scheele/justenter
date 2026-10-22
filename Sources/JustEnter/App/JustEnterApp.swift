import AppKit
import SwiftUI

@main
struct JustEnterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContent(appState: delegate.appState, openWindow: { openWindow(id: $0) })
        } label: {
            MenuBarLabel(appState: delegate.appState)
        }

        Window("History", id: "history") {
            HistoryView(store: delegate.appState.history)
        }
        .defaultSize(width: 800, height: 500)

        Settings {
            SettingsView(appState: delegate.appState)
        }
    }

}

/// Lives inside the MenuBarExtra label so it actually re-renders on state changes:
/// recording/processing states, and the active mode's icon flashed after a switch.
private struct MenuBarLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        switch appState.phase {
        case .recording: return "waveform.circle.fill"
        case .transcribing, .enhancing, .preparing: return "ellipsis.circle"
        default: return appState.menuBarModeSymbol ?? "waveform"
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var appState: AppState
    let openWindow: (String) -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(appState.phase == .recording ? "Stop & Insert" : "Start Dictation") {
            appState.toggleRecording()
        }
        .keyboardShortcut(.space, modifiers: .option)

        if appState.isDictating {
            Button("Cancel Dictation (Esc)") {
                appState.cancelDictation()
            }
        }

        Divider()

        Picker("Mode", selection: Binding(
            get: { appState.modesStore.activeModeID },
            set: { id in
                if let mode = appState.modesStore.modes.first(where: { $0.id == id }) {
                    appState.modesStore.select(mode, manual: true)
                }
            }
        )) {
            ForEach(appState.modesStore.modes) { mode in
                Label(mode.name, systemImage: mode.symbol).tag(mode.id)
            }
        }
        .pickerStyle(.inline)

        Divider()

        Button("History…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow("history")
        }
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
            SettingsView.bringToFront()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit JustEnter") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let appState = AppState()
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            appState.start()
            if !AppSettings.shared.hasCompletedOnboarding {
                showOnboarding()
            }
        }
    }

    @MainActor
    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView { [weak window] in
            window?.close()
        })
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
