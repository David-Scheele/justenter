import AppKit
import SwiftUI

/// Borderless, non-activating panel hosting the floating bubble.
final class BubblePanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Keeps a small bubble pinned top-center of the active screen, just below the
/// menu bar — same look on every display, no notch involved.
@MainActor
final class BubbleController {
    private let panel = BubblePanel()
    private let hosting: NSHostingView<BubbleView>
    private let stageSize = NSSize(width: 420, height: 380)

    init(appState: AppState) {
        hosting = NSHostingView(rootView: BubbleView(appState: appState))
        hosting.frame = NSRect(origin: .zero, size: stageSize)
        panel.contentView = hosting
        reposition()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in self.reposition() }
        }
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// The panel swallows clicks only while the mode dropdown is open.
    func setInteractive(_ interactive: Bool) {
        panel.ignoresMouseEvents = !interactive
    }

    private func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = NSRect(
            x: screen.frame.midX - stageSize.width / 2,
            y: screen.visibleFrame.maxY - stageSize.height - 6,
            width: stageSize.width,
            height: stageSize.height
        )
        panel.setFrame(frame, display: true)
    }
}
