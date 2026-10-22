import SwiftUI

/// Superwhisper-style Home: usage stats up top, recent dictations below.
struct HomePane: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var records: [HistoryRecord] { appState.history.records }

    private var totalWords: Int {
        records.reduce(0) { $0 + $1.finalText.split(separator: " ").count }
    }

    private var totalDuration: TimeInterval {
        records.reduce(0) { $0 + $1.duration }
    }

    private var averageWPM: Int {
        guard totalDuration > 5 else { return 0 }
        return Int(Double(totalWords) / (totalDuration / 60))
    }

    /// Versus typing at ~35 words per minute.
    private var savedMinutes: Int {
        let typingMinutes = Double(totalWords) / 35.0
        return max(0, Int(typingMinutes - totalDuration / 60))
    }

    private var appsUsed: Int {
        Set(records.map(\.appName)).count
    }

    var body: some View {
        PaneScaffold(title: "Home") {
            SettingsCard {
                HStack(alignment: .top, spacing: 0) {
                    stat(value: "\(averageWPM) WPM", label: "Average speed")
                    stat(value: "\(totalWords)", label: "Words")
                    stat(value: "\(appsUsed)", label: "Apps used")
                    stat(value: savedMinutes >= 60 ? "\(savedMinutes / 60) h \(savedMinutes % 60) m" : "\(savedMinutes) min", label: "Saved all time")
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
            }

            HStack {
                PaneSectionTitle("Recent dictations")
                Spacer()
                Button("See all") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "history")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            }

            if records.isEmpty {
                SettingsCard {
                    Text("Nothing yet — hold \(appState.settings.recordHotkey.display) and start talking.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(records.prefix(6)) { record in
                    recordCard(record)
                }
            }
        }
    }

    @ViewBuilder
    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func recordCard(_ record: HistoryRecord) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 5) {
                Text(record.finalText)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text(record.modeName)
                    Text("·")
                    Text(record.appName)
                    Text("·")
                    Text(record.date, style: .relative)
                    Spacer()
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.finalText, forType: .string)
            }
            Button("Copy Raw Transcript") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.rawTranscript, forType: .string)
            }
            Button("Delete", role: .destructive) {
                appState.history.delete(record)
            }
        }
    }
}
