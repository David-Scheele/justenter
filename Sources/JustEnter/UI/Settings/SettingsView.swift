import SwiftUI
import AppKit

/// Settings shell styled like macOS System Settings: a sidebar with colored
/// icon chips on the left, the selected pane as a grouped form on the right.
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selection: Pane? = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general, modes, ai, speech, vocabulary, knowledge

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .modes: return "Modes"
            case .ai: return "AI"
            case .speech: return "Speech"
            case .vocabulary: return "Vocabulary"
            case .knowledge: return "Knowledge"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .modes: return "square.grid.2x2.fill"
            case .ai: return "sparkles"
            case .speech: return "waveform"
            case .vocabulary: return "character.book.closed.fill"
            case .knowledge: return "brain.fill"
            }
        }

        var color: Color {
            switch self {
            case .general: return .gray
            case .modes: return .indigo
            case .ai: return .purple
            case .speech: return .blue
            case .vocabulary: return .orange
            case .knowledge: return .teal
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(pane.color.gradient, in: RoundedRectangle(cornerRadius: 6))
                }
                .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
        } detail: {
            detailView(for: selection ?? .general)
                .navigationTitle((selection ?? .general).title)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(width: 840, height: 580)
        .onAppear { Self.bringToFront() }
    }

    @ViewBuilder
    private func detailView(for pane: Pane) -> some View {
        switch pane {
        case .general:
            GeneralSettingsView(appState: appState)
        case .modes:
            ModesSettingsView(appState: appState)
        case .ai:
            AISettingsView()
        case .speech:
            SpeechSettingsView(appState: appState)
        case .vocabulary:
            VocabularySettingsView(store: appState.vocabulary)
        case .knowledge:
            KnowledgeSettingsView(store: appState.knowledge)
        }
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
