import Foundation
import Combine

@MainActor
final class ModesStore: ObservableObject {
    @Published var modes: [Mode] {
        didSet { Persistence.save(modes, to: "modes.json") }
    }
    @Published var activeModeID: UUID {
        didSet { UserDefaults.standard.set(activeModeID.uuidString, forKey: "activeModeID") }
    }
    /// True while the user has manually picked a mode; auto-switching resumes on next app change.
    var manuallyPinned = false

    init() {
        var loaded = Persistence.load([Mode].self, from: "modes.json") ?? Mode.defaults()
        // Inject the Auto mode once; it becomes the active default when first added.
        var autoJustAdded: UUID?
        if !loaded.contains(where: { $0.isAuto }) {
            let auto = Mode.autoMode()
            loaded.insert(auto, at: 0)
            autoJustAdded = auto.id
        }
        modes = loaded
        if let autoJustAdded {
            activeModeID = autoJustAdded
        } else if let raw = UserDefaults.standard.string(forKey: "activeModeID"),
                  let id = UUID(uuidString: raw),
                  loaded.contains(where: { $0.id == id }) {
            activeModeID = id
        } else {
            activeModeID = loaded.first?.id ?? UUID()
        }
        Persistence.save(modes, to: "modes.json")
    }

    var activeMode: Mode {
        modes.first(where: { $0.id == activeModeID }) ?? modes.first ?? Mode(name: "Transcription", aiEnabled: false)
    }

    func select(_ mode: Mode, manual: Bool = false) {
        activeModeID = mode.id
        manuallyPinned = manual
    }

    /// Returns the mode that claims this bundle identifier, if any.
    func mode(for bundleID: String) -> Mode? {
        modes.first(where: { !$0.isAuto && $0.activationBundleIDs.contains(bundleID) })
    }

    func add(_ mode: Mode) {
        modes.append(mode)
    }

    func update(_ mode: Mode) {
        if let idx = modes.firstIndex(where: { $0.id == mode.id }) {
            modes[idx] = mode
        }
    }

    func delete(_ mode: Mode) {
        modes.removeAll { $0.id == mode.id }
        if activeModeID == mode.id, let first = modes.first {
            activeModeID = first.id
        }
    }
}
