import AppKit

final class InputPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return nil to allow all mouse events to pass through to underlying views
        return nil
    }
}
