import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState)
                .tabItem { Label("General", systemImage: "gearshape") }
            ModesSettingsView(appState: appState)
                .tabItem { Label("Modes", systemImage: "square.grid.2x2") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
            SpeechSettingsView(appState: appState)
                .tabItem { Label("Speech", systemImage: "waveform") }
            VocabularySettingsView(store: appState.vocabulary)
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            KnowledgeSettingsView(store: appState.knowledge)
                .tabItem { Label("Knowledge", systemImage: "brain") }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { Self.bringToFront() }
    }

    /// Menu-bar (accessory) apps don't activate when the Settings scene opens, so the
    /// window never becomes key and text fields ignore the keyboard. Force it.
    static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let settingsWindow = NSApp.windows.first {
                $0.identifier?.rawValue.contains("Settings") == true
            } ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey && !($0 is BubblePanel) }
            settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }
}
