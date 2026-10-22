import AppKit
import Carbon.HIToolbox

struct Hotkey: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let defaultRecord = Hotkey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey))
    static let defaultModeSwitch = Hotkey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey | shiftKey))

    var stringValue: String { "\(keyCode),\(carbonModifiers)" }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(stringValue: String?) {
        guard let stringValue else { return nil }
        let parts = stringValue.split(separator: ",")
        guard parts.count == 2, let code = UInt32(parts[0]), let mods = UInt32(parts[1]) else { return nil }
        self.init(keyCode: code, carbonModifiers: mods)
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        carbonModifiers = mods
    }

    var display: String {
        var parts = ""
        if carbonModifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + Self.keyName(for: keyCode)
    }

    static func keyName(for keyCode: UInt32) -> String {
        let special: [UInt32: String] = [
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "⎋", UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        ]
        if let name = special[keyCode] { return name }

        // Translate through the current keyboard layout.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
            let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
