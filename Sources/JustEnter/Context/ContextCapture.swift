import AppKit
import ApplicationServices

/// Best-effort capture of the text selected in the frontmost app (via the
/// Accessibility API) and the clipboard, for context-aware modes.
enum ContextCapture {
    static func selectedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef
        else { return nil }
        let focused = focusedRef as! AXUIElement

        var selectionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectionRef) == .success,
              let text = selectionRef as? String,
              !text.isEmpty
        else { return nil }
        // Keep context bounded so prompts stay small.
        return String(text.prefix(4000))
    }

    static func clipboardText() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return nil }
        return String(text.prefix(4000))
    }
}
