import AppKit
import Combine

/// Tracks the frontmost application and reports changes so modes can auto-switch.
@MainActor
final class AppWatcher: ObservableObject {
    @Published private(set) var frontmostName: String?
    @Published private(set) var frontmostBundleID: String?

    var onChange: ((_ bundleID: String, _ name: String) -> Void)?

    private var observer: NSObjectProtocol?

    func start() {
        capture(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                self?.capture(app)
            }
        }
    }

    private func capture(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        frontmostName = app.localizedName
        frontmostBundleID = app.bundleIdentifier
        if let bundleID = app.bundleIdentifier {
            onChange?(bundleID, app.localizedName ?? bundleID)
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
