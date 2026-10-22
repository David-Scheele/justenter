import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon. Delivers both press and release so the
/// caller can implement Superwhisper-style dual behavior: quick tap toggles recording,
/// press-and-hold works as push-to-talk (stops when released).
@MainActor
final class HotkeyManager {
    enum Action: UInt32 {
        case record = 1
        case modeSwitch = 2
        case cancel = 3
        case digit1 = 11, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9

        /// 0-based index for the digit actions, nil otherwise.
        var digitIndex: Int? {
            guard rawValue >= Action.digit1.rawValue, rawValue <= Action.digit9.rawValue else { return nil }
            return Int(rawValue - Action.digit1.rawValue)
        }

        static let digits: [Action] = [.digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9]
    }

    var onPress: ((Action) -> Void)?
    var onRelease: ((Action) -> Void)?

    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    func start() {
        guard handlerRef == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotkeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID
            )
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let kind = GetEventKind(event)
            guard let action = Action(rawValue: hotkeyID.id) else { return noErr }
            DispatchQueue.main.async {
                if kind == UInt32(kEventHotKeyPressed) {
                    manager.onPress?(action)
                } else {
                    manager.onRelease?(action)
                }
            }
            return noErr
        }, eventTypes.count, &eventTypes, selfPtr, &handlerRef)
    }

    func register(_ hotkey: Hotkey, for action: Action) {
        unregister(action)
        var ref: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: OSType(0x4A_45_4E_54) /* 'JENT' */, id: action.rawValue)
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.carbonModifiers, hotkeyID,
            GetEventDispatcherTarget(), 0, &ref
        )
        if status == noErr, let ref {
            hotkeyRefs[action.rawValue] = ref
        }
    }

    func unregister(_ action: Action) {
        if let existing = hotkeyRefs.removeValue(forKey: action.rawValue) {
            UnregisterEventHotKey(existing)
        }
    }
}
