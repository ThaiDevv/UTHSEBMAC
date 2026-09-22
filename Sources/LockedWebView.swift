import AppKit
import WebKit

final class LockedWebView: WKWebView {
    override func rightMouseDown(with event: NSEvent) {
        // Suppress right-click context menu (Inspect Element, Save As, Reload, etc.)
    }
    
    override func otherMouseDown(with event: NSEvent) {
        // Suppress middle click or other mouse button shortcuts
    }
}
