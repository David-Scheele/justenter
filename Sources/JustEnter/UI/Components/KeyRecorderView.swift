import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A capsule that records the next key combination pressed while active.
struct KeyRecorderView: View {
    @Binding var hotkey: Hotkey
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Press keys…" : hotkey.display)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(minWidth: 110)
                .padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .orange : nil)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                stopRecording()
                return nil
            }
            hotkey = Hotkey(event: event)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
