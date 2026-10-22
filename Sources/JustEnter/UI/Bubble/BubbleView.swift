import SwiftUI

/// The small floating capsule: mode icon on the left, a voice-reactive wave while
/// listening, a spinner while working. The mode dropdown appears right below it.
struct BubbleView: View {
    @ObservedObject var appState: AppState

    private var phase: DictationPhase { appState.phase }

    private var isVisible: Bool {
        phase != .idle || appState.modeDropdownVisible
    }

    var body: some View {
        VStack(spacing: 8) {
            bubble
            if appState.modeDropdownVisible {
                ModeDropdownView(appState: appState)
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(appState.modeDropdownVisible)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: appState.modeDropdownVisible)
        .animation(.easeInOut(duration: 0.18), value: isVisible)
    }

    @ViewBuilder
    private var bubble: some View {
        HStack(spacing: 6) {
            switch phase {
            case .recording:
                WaveformBars(recorder: appState.recorder)
                    .frame(width: 46, height: 11)
            case .preparing:
                Spinner()
                    .frame(width: 10, height: 10)
                Text(appState.preparingStatus)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            case .transcribing, .enhancing:
                Spinner()
                    .frame(width: 10, height: 10)
                    .frame(width: 46)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46)
                    .transition(.scale.combined(with: .opacity))
            case .error(let message):
                Text(message)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 260)
            case .idle:
                // Dropdown open while idle: flat dotted wave placeholder.
                WaveformBars(recorder: appState.recorder)
                    .frame(width: 46, height: 11)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 22)
        // Liquid Glass HUD, dark-tinted like the system volume/brightness OSD.
        .glassEffect(.regular.tint(.black.opacity(0.45)), in: Capsule())
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: phaseKey)
    }

    private var phaseKey: Int {
        switch phase {
        case .idle: return 0
        case .recording: return 1
        case .transcribing: return 2
        case .enhancing: return 3
        case .done: return 4
        case .error: return 5
        case .preparing: return 6
        }
    }
}

/// Dropdown listing all modes, styled like a native macOS menu: system material,
/// checkmark column, accent-color highlight on hover, digits as shortcut labels.
struct ModeDropdownView: View {
    @ObservedObject var appState: AppState
    @State private var hoveredModeID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(appState.modesStore.modes.enumerated()), id: \.element.id) { index, mode in
                row(index: index, mode: mode)
            }
        }
        .padding(5)
        .frame(width: 230)
        // Liquid Glass panel, like native Tahoe menus.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }

    @ViewBuilder
    private func row(index: Int, mode: Mode) -> some View {
        let isActive = mode.id == appState.modesStore.activeModeID
        let isHighlighted = hoveredModeID == mode.id
        Button {
            appState.selectModeFromDropdown(mode)
        } label: {
            HStack(spacing: 0) {
                // Checkmark column, like a real menu.
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, alignment: .leading)
                    .opacity(isActive ? 1 : 0)
                Image(systemName: mode.symbol)
                    .font(.system(size: 12))
                    .frame(width: 20, alignment: .leading)
                Text(mode.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 13))
                        .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                }
            }
            .foregroundStyle(isHighlighted ? .white : .primary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                isHighlighted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredModeID = hovering ? mode.id : (hoveredModeID == mode.id ? nil : hoveredModeID)
        }
    }
}

/// The listening wave: rounded bars whose heights scroll with the live microphone
/// level. Speaking makes it dance; silence is a flat dotted line.
struct WaveformBars: View {
    @ObservedObject var recorder: AudioRecorder
    private let barCount = 12

    var body: some View {
        Canvas { context, size in
            let recent = Array(recorder.levels.suffix(barCount))
            let barWidth = size.width / CGFloat(barCount) * 0.5
            let gap = size.width / CGFloat(barCount)
            for i in 0..<barCount {
                // Soft noise gate keeps a quiet room flat, then a perceptual curve
                // boosts normal speaking volume so you don't have to shout.
                let raw = i < recent.count ? CGFloat(recent[i]) : 0
                let gated = max(0, raw - 0.08) / 0.92
                let voice = min(pow(gated, 0.5) * 1.4, 1)
                let height = max(barWidth, size.height * voice)
                let x = CGFloat(i) * gap + (gap - barWidth) / 2
                let y = (size.height - height) / 2
                let bar = Path(
                    roundedRect: CGRect(x: x, y: y, width: barWidth, height: height),
                    cornerRadius: barWidth / 2
                )
                let alpha = 0.45 + 0.55 * voice
                context.fill(bar, with: .color(.white.opacity(alpha)))
            }
        }
        .animation(.linear(duration: 0.05), value: recorder.levels)
    }
}

/// Small rotating arc spinner for every waiting state.
struct Spinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let angle = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.0) * 360
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.white.opacity(0), .white]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .rotationEffect(.degrees(angle))
        }
    }
}
