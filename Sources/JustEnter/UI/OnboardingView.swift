import SwiftUI

/// First-run welcome: permissions, API key, and the essential hotkeys —
/// dressed in Liquid Glass.
struct OnboardingView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var micGranted = Permissions.microphoneGranted
    @State private var axGranted = Permissions.accessibilityGranted
    var onDone: () -> Void

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.10, blue: 0.16),
                    Color(red: 0.16, green: 0.12, blue: 0.20),
                    Color(red: 0.24, green: 0.14, blue: 0.16),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                    Text("JustEnter")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Speak anywhere. AI writes it properly.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.top, 28)

                VStack(spacing: 12) {
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
                    apiKeyCard
                }
                .padding(.horizontal, 26)

                VStack(spacing: 4) {
                    Text("Hold **\(settings.recordHotkey.display)** and talk — release to insert.")
                    Text("Tap it to toggle · **\(settings.modeSwitchHotkey.display)** cycles modes · **Esc** cancels")
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))

                Button {
                    settings.hasCompletedOnboarding = true
                    onDone()
                } label: {
                    Text("Start dictating")
                        .font(.headline)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Color(red: 0.85, green: 0.47, blue: 0.34))
                .padding(.bottom, 26)
            }
        }
        .frame(width: 560, height: 610)
        .onReceive(timer) { _ in
            micGranted = Permissions.microphoneGranted
            axGranted = Permissions.accessibilityGranted
        }
    }

    @ViewBuilder
    private func stepCard(done: Bool, title: String, subtitle: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 22))
                .foregroundStyle(done ? .green : .white.opacity(0.5))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            if !done {
                Button(buttonTitle, action: action)
                    .buttonStyle(.glass)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var apiKeyCard: some View {
        HStack(spacing: 14) {
            Image(systemName: LocalAIService.isAvailable ? "checkmark.circle.fill" : "brain")
                .font(.system(size: 22))
                .foregroundStyle(LocalAIService.isAvailable ? .green : .white.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text("On-device AI")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(LocalAIService.isAvailable
                    ? "Apple Intelligence rewrites your dictation locally — nothing leaves this Mac."
                    : LocalAIService.availabilityDescription + ". Dictation works without it — raw transcripts are inserted.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
