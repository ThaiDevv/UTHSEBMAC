import AppKit

final class KioskWindow: NSWindow {
    var onEscapePressed: (() -> Void)?
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    override func sendEvent(_ event: NSEvent) {
        // macOS virtual keycode 0x35 (53) is the Escape key
        if event.type == .keyDown && event.keyCode == 0x35 {
            if let onEscapePressed = onEscapePressed {
                onEscapePressed()
                return
            }
        }
        super.sendEvent(event)
    }
}
