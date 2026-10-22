import SwiftUI

/// First-run welcome: permissions and the essential hotkeys — native macOS
/// styling: system typography, system colors, accent-tinted controls.
struct OnboardingView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var micGranted = Permissions.microphoneGranted
    @State private var axGranted = Permissions.accessibilityGranted
    var onDone: () -> Void

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                Text("JustEnter")
                    .font(.system(size: 26, weight: .bold))
                Text("Speak anywhere. AI writes it properly — entirely on this Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 30)

            VStack(spacing: 10) {
                stepCard(
                    done: micGranted,
                    title: "Microphone access",
                    subtitle: "Works with any input — built-in, AirPods, USB.",
                    buttonTitle: "Allow"
                ) {
                    Task { micGranted = await Permissions.requestMicrophone() }
                }
                stepCard(
                    done: axGranted,
                    title: "Accessibility access",
                    subtitle: "Lets JustEnter paste text and read your selection for context.",
                    buttonTitle: "Grant"
                ) {
                    Permissions.requestAccessibility()
                }
                aiCard
            }
            .padding(.horizontal, 24)

            VStack(spacing: 3) {
                Text("Hold \(settings.recordHotkey.display) and talk — release to insert.")
                Text("Tap it to toggle · \(settings.modeSwitchHotkey.display) cycles modes · Esc cancels")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Button {
                settings.hasCompletedOnboarding = true
                onDone()
            } label: {
                Text("Start Dictating")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 26)
        }
        .frame(width: 540, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(timer) { _ in
            micGranted = Permissions.microphoneGranted
            axGranted = Permissions.accessibilityGranted
        }
    }

    @ViewBuilder
    private func stepCard(done: Bool, title: String, subtitle: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 20))
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !done {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var aiCard: some View {
        HStack(spacing: 12) {
            Image(systemName: LocalAIService.isAvailable ? "checkmark.circle.fill" : "brain")
                .font(.system(size: 20))
                .foregroundStyle(LocalAIService.isAvailable ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 2) {
                Text("On-device AI")
                    .font(.system(size: 13, weight: .semibold))
                Text(LocalAIService.isAvailable
                    ? "Apple Intelligence rewrites your dictation locally — nothing leaves this Mac."
                    : LocalAIService.availabilityDescription + ". Dictation works without it — raw transcripts are inserted.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
