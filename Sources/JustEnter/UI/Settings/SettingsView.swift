import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        // The modern Tab API gives the native toolbar-style settings tabs
        // (Liquid Glass chrome) instead of the legacy boxed tab view.
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(appState: appState)
            }
            Tab("Modes", systemImage: "square.grid.2x2") {
                ModesSettingsView(appState: appState)
            }
            Tab("AI", systemImage: "sparkles") {
                AISettingsView()
            }
            Tab("Speech", systemImage: "waveform") {
                SpeechSettingsView(appState: appState)
            }
            Tab("Vocabulary", systemImage: "character.book.closed") {
                VocabularySettingsView(store: appState.vocabulary)
            }
            Tab("Knowledge", systemImage: "brain") {
                KnowledgeSettingsView(store: appState.knowledge)
            }
        }
        .frame(width: 680, height: 560)
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
