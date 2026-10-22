import SwiftUI
import AppKit

/// Settings window modeled on Superwhisper: custom sidebar with colored icon
/// chips, card-based panes, inset traffic lights, update button bottom-left.
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selection: Pane = .home

    enum Pane: String, CaseIterable, Identifiable {
        case home, modes, vocabulary, knowledge
        case configuration, sound, models

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return "Home"
            case .modes: return "Modes"
            case .vocabulary: return "Vocabulary"
            case .knowledge: return "Knowledge"
            case .configuration: return "Configuration"
            case .sound: return "Sound"
            case .models: return "Models library"
            }
        }

        var symbol: String {
            switch self {
            case .home: return "house.fill"
            case .modes: return "sparkles"
            case .vocabulary: return "character.book.closed.fill"
            case .knowledge: return "brain.fill"
            case .configuration: return "gearshape.fill"
            case .sound: return "speaker.wave.2.fill"
            case .models: return "books.vertical.fill"
            }
        }

        var color: Color {
            switch self {
            case .home: return .orange
            case .modes: return .indigo
            case .vocabulary: return .blue
            case .knowledge: return .teal
            case .configuration: return .gray
            case .sound: return .gray
            case .models: return .gray
            }
        }

        static let primary: [Pane] = [.home, .modes, .vocabulary, .knowledge]
        static let secondary: [Pane] = [.configuration, .sound, .models]
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.4)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 960, height: 640)
        .ignoresSafeArea()
        .onAppear { Self.bringToFront() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Clearance for the inset traffic lights and the toolbar's click-dead strip.
            Spacer().frame(height: 56)
            ForEach(Pane.primary) { pane in
                sidebarRow(pane)
            }
            Spacer().frame(height: 18)
            ForEach(Pane.secondary) { pane in
                sidebarRow(pane)
            }
            Spacer()
            updateFooter
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(width: 215)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func sidebarRow(_ pane: Pane) -> some View {
        Button {
            selection = pane
        } label: {
            HStack(spacing: 9) {
                IconChip(symbol: pane.symbol, color: pane.color)
                Text(pane.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                selection == pane ? AnyShapeStyle(.quaternary.opacity(0.8)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Update footer (bottom-left, where Superwhisper puts its branding)

    private var updateFooter: some View {
        UpdateFooter()
    }
}

/// Version + update action pinned to the sidebar bottom.
private struct UpdateFooter: View {
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 6) {
            Text("JustEnter v\(UpdateChecker.currentVersion)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
            switch updater.status {
            case .available(let version):
                Button {
                    Task { await updater.installUpdate() }
                } label: {
                    Text("Install Update v\(version)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            case .checking:
                Button {} label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Checking…")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            case .downloading, .installing:
                Button {} label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Updating…")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            case .failed:
                Button {
                    Task { await updater.check() }
                } label: {
                    Text("Update check failed — retry")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            case .idle, .upToDate:
                Button {
                    Task { await updater.check() }
                } label: {
                    Text("No updates available")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

extension SettingsView {
    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home:
            HomePane(appState: appState)
        case .modes:
            ModesPane(appState: appState)
        case .vocabulary:
            VocabularyPane(store: appState.vocabulary)
        case .knowledge:
            KnowledgePane(store: appState.knowledge)
        case .configuration:
            ConfigurationPane(appState: appState)
        case .sound:
            SoundPane()
        case .models:
            ModelsLibraryPane(appState: appState)
        }
    }

    // MARK: - Window chrome

    /// Accessory apps don't activate when Settings opens (text fields would ignore
    /// the keyboard), and the window gets the Superwhisper-style chrome: hidden
    /// title, inset traffic lights (via unified toolbar height), no zoom button.
    static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window = NSApp.windows.first(where: {
                $0.identifier?.rawValue.contains("Settings") == true
            }) ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey && !($0 is BubblePanel) })
            else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            if window.toolbar == nil {
                let toolbar = NSToolbar()
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
                window.toolbarStyle = .unified
            }
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.makeKeyAndOrderFront(nil)
        }
    }
}
