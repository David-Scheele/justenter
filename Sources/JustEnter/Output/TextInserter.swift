import AppKit
import Carbon.HIToolbox

/// Delivers the final text straight to the cursor in whatever input field has focus:
/// copies it to the pasteboard and synthesizes ⌘V, then restores the previous clipboard.
@MainActor
enum TextInserter {
    static func insert(_ text: String, restoreClipboard: Bool) {
        let pasteboard = NSPasteboard.general
        let savedItems: [NSPasteboardItem] = restoreClipboard ? snapshot(pasteboard) : []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Without Accessibility we can't synthesize the keystroke — text stays on the clipboard.
        guard AXIsProcessTrusted() else { return }
        sendCmdV()

        if restoreClipboard, !savedItems.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                pasteboard.clearContents()
                pasteboard.writeObjects(savedItems)
            }
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                // Skip huge payloads (screenshots etc.) — copying them in and out
                // of memory would delay the paste for marginal benefit.
                if let data = item.data(forType: type), data.count < 4_000_000 {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func sendCmdV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
