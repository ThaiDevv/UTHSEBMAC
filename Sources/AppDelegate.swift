import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, NSWindowDelegate {
    private var window: KioskWindow?
    private var webView: LockedWebView?
    private var loadingOverlay: NSView?
    private var loadingLabel: NSTextField?
    private var screenTimer: Timer?
    private var keyboardMonitor: Any?
    private var runningApplicationsObservation: NSKeyValueObservation?
    private var launchTimeoutWorkItem: DispatchWorkItem?
    private var currentLaunchTarget: URL?
    private var pendingIncomingURL: URL?
    private var blockedNavigationHandled = false
    private var exitConfirmationOpen = false
    private var exitConfirmationOverlay: NSView?
    private weak var exitConfirmationPreviousResponder: NSResponder?
    private var isShowingLauncher = false
    private var browserLaunchGraceUntil = Date()
    private var sessionValidated = false
    private var cachedLicenseToken: String?
    
    private let version = "1.0.4"
    private let launchTimeoutSeconds: TimeInterval = 25.0
    private let exitInstructionText = "Cách thoát UTH SEB: nhấn phím Esc, sau đó chọn Thoát."
    
    private let browserProcessTerms: [String] = [
        "google chrome", "chrome", "firefox", "microsoft edge",
        "brave browser", "brave", "opera", "vivaldi",
        "chromium", "tor browser", "waterfox", "librewolf", "coc coc"
    ]
    
    private let forbiddenProcessTerms: [String] = [
        "obs", "camtasia", "screen recorder", "teamviewer", "ultraviewer",
        "anydesk", "rustdesk", "supremo", "nomachine", "parsec",
        "screenconnect", "connectwise", "splashtop", "remote desktop",
        "vnc", "zoom", "skype", "discord", "microsoft teams", "teams",
        "webex", "gotomeeting", "bluejeans", "slack", "telegram", "whatsapp",
        "copilot", "microsoft copilot", "quicktime player",
        "google chrome", "chrome", "firefox", "microsoft edge",
        "brave browser", "brave", "opera", "vivaldi",
        "chromium", "tor browser", "waterfox", "librewolf", "coc coc"
    ]
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if blockVirtualMachineIfDetected() {
            return
        }
        
        checkForbiddenProcesses()
        observeRunningApplications()
        installKeyboardMonitor()
        startScreenTimer()
        createWindow()
        
        if let target = pendingIncomingURL {
            pendingIncomingURL = nil
            navigateToLaunchTarget(target)
        } else {
            showLauncher()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NSApp.presentationOptions = []
        screenTimer?.invalidate()
        screenTimer = nil
        launchTimeoutWorkItem?.cancel()
        launchTimeoutWorkItem = nil
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        runningApplicationsObservation?.invalidate()
        runningApplicationsObservation = nil
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if window != nil {
            handleIncomingURL(url)
        } else {
            pendingIncomingURL = url
        }
    }
    
    // MARK: - Virtual Machine Check
    
    @discardableResult
    private func blockVirtualMachineIfDetected() -> Bool {
        let result = VirtualMachineDetector.detect()
        if result.isVirtualMachine {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = String(format: "Virtual machine blocked: %@", result.reason)
            alert.informativeText = "Vui lòng không sử dụng máy ảo để tham gia thi."
            alert.addButton(withTitle: "Thoát")
            alert.runModal()
            NSApp.terminate(nil)
            return true
        }
        return false
    }
    
    // MARK: - Window & Web View Initialization
    
    private func createWindow() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.frame
        
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.websiteDataStore = .nonPersistent()
        config.applicationNameForUserAgent = "UTHSEB/\(version) (Official Build; School-ID: UTH-2026; SecureMode)"
        
        // Setup WebKit message handler for AI Moodle & License bridge
        config.userContentController.add(self, name: "uthseb")
        
        let polyfillSource = """
        if (!window.chrome) { window.chrome = {}; }
        if (!window.chrome.webview) {
            window.chrome.webview = {
                postMessage: function(msg) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.uthseb) {
                        window.webkit.messageHandlers.uthseb.postMessage(msg);
                    }
                },
                addEventListener: function(event, callback) {
                    window.addEventListener(event, function(e) { callback(e); });
                }
            };
        }
        """
        let polyfillScript = WKUserScript(source: polyfillSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(polyfillScript)
        
        let web = LockedWebView(frame: screenRect, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.autoresizingMask = [.width, .height]
        self.webView = web
        
        let win = KioskWindow(
            contentRect: screenRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullScreen],
            backing: .buffered,
            defer: false
        )
        win.title = "UTH SEB v\(version)"
        win.level = .normal
        win.collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]
        win.backgroundColor = .black
        win.isOpaque = true
        win.hasShadow = false
        win.contentView = web
        win.delegate = self
        win.onEscapePressed = { [weak self] in
            self?.requestExitConfirmation()
        }
        
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Tự động vào chế độ Toàn màn hình (Full Screen) khi mở app
        DispatchQueue.main.async {
            if let window = self.window, !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
        
        // Khóa chặt Kiosk Mode: Cấm chuyển tiến trình (Command + Tab), ẩn Dock và MenuBar
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableAppleMenu
        ]
    }
    
    // MARK: - NSWindowDelegate
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestExitConfirmation()
        return false
    }
    
    // MARK: - Keyboard Monitoring
    
    private func installKeyboardMonitor() {
        let blockedCommandKeys: Set<String> = ["q", "w", "m", "h", "r", "l", "n", "t", ",", "`"]
        let blockedControlKeys: Set<String> = ["3", "4", "5"]
        
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Escape key
            if event.keyCode == 0x35 {
                if self.exitConfirmationOpen {
                    self.dismissExitConfirmation()
                } else {
                    self.requestExitConfirmation()
                }
                return nil
            }
            
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let flags = event.modifierFlags
            
            if flags.contains(.command) {
                if blockedCommandKeys.contains(chars) {
                    return nil
                }
            }
            
            if flags.contains(.control) {
                if blockedControlKeys.contains(chars) {
                    return nil
                }
            }
            
            return event
        }
    }
    
    // MARK: - Multi-screen Enforcement
    
    private func startScreenTimer() {
        screenTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.enforceSingleScreen()
        }
    }
    
    private func enforceSingleScreen() {
        if NSScreen.screens.count >= 2 {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Cảnh báo gian lận"
            alert.informativeText = "Phát hiện sử dụng nhiều màn hình. Vui lòng rút màn hình phụ và khởi động lại ứng dụng."
            alert.addButton(withTitle: "Thoát")
            if let win = self.window {
                alert.window.level = NSWindow.Level(max(win.level.rawValue + 1, NSWindow.Level.modalPanel.rawValue))
            }
            alert.window.orderFrontRegardless()
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
    
    // MARK: - Process Monitoring
    
    private func checkForbiddenProcesses() {
        for app in NSWorkspace.shared.runningApplications {
            checkForbiddenApplication(app)
        }
    }
    
    private func observeRunningApplications() {
        runningApplicationsObservation = NSWorkspace.shared.observe(
            \.runningApplications,
            options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.checkForbiddenProcesses()
            }
        }
    }
    
    private func checkForbiddenApplication(_ app: NSRunningApplication) {
        let appName = (app.localizedName ?? app.bundleIdentifier ?? "").lowercased()
        guard !appName.isEmpty else { return }
        
        for term in forbiddenProcessTerms {
            if appName.contains(term) {
                app.forceTerminate()
                break
            }
        }
    }
    
    // MARK: - Navigation & Launcher
    
    private func showLauncher() {
        isShowingLauncher = true
        currentLaunchTarget = nil
        hideLaunchLoading()
        
        guard let htmlURL = Bundle.main.url(forResource: "launcher", withExtension: "html"),
              let template = try? String(contentsOf: htmlURL, encoding: .utf8) else {
            webView?.loadHTMLString("<h2>Lỗi nạp launcher</h2>", baseURL: nil)
            return
        }
        
        var bgImageCSS = ""
        if let bgURL = Bundle.main.url(forResource: "bgcourses", withExtension: "jpg"),
           let imgData = try? Data(contentsOf: bgURL) {
            let base64 = imgData.base64EncodedString()
            bgImageCSS = "linear-gradient(rgba(8, 20, 36, 0.24), rgba(8, 20, 36, 0.24)), url(\"data:image/jpeg;base64,\(base64)\")"
        }
        
        var html = template
        // Replace background image placeholder
        if let bgRange = html.range(of: "background-image:     ;") {
            html.replaceSubrange(bgRange, with: "background-image: \(bgImageCSS);")
        }
        // Replace exit-note placeholder
        if let exitNoteRange = html.range(of: "<p class=\"exit-note\">             </p>") {
            html.replaceSubrange(exitNoteRange, with: "<p class=\"exit-note\">\(exitInstructionText)</p>")
        }
        // Replace version placeholder
        if let versionRange = html.range(of: "v               </span>") {
            html.replaceSubrange(versionRange, with: "v\(version)</span>")
        }
        
        webView?.loadHTMLString(html, baseURL: nil)
    }
    
    private func handleIncomingURL(_ url: URL) {
        if let target = DomainPolicy.launchTarget(from: url) {
            navigateToLaunchTarget(target)
        } else {
            showBlockedNavigation(url)
        }
    }
    
    private func navigateToLaunchTarget(_ targetURL: URL) {
        isShowingLauncher = false
        currentLaunchTarget = targetURL
        showLaunchLoading(targetURL)
        
        let request = URLRequest(url: targetURL)
        let signedRequest = RequestAuthenticator.addingHash(to: request)
        webView?.load(signedRequest)
    }
    
    private func showLaunchLoading(_ targetURL: URL) {
        hideLaunchLoading()
        guard let parentView = window?.contentView else { return }
        
        let overlay = NSView(frame: parentView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 14
        overlay.addSubview(card)
        
        let titleLabel = NSTextField(labelWithString: "ĐANG MỞ BÀI THI")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 20, weight: .heavy)
        titleLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.29, blue: 0.50, alpha: 1.0)
        titleLabel.alignment = .center
        card.addSubview(titleLabel)
        
        let subtitleLabel = NSTextField(labelWithString: "UTH SEB đang tải trang trong chế độ an toàn...\nVui lòng chờ trong giây lát")
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        self.loadingLabel = subtitleLabel
        card.addSubview(subtitleLabel)
        
        let spinner = NSProgressIndicator()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        card.addSubview(spinner)
        
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 380),
            card.heightAnchor.constraint(equalToConstant: 190),
            
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16)
        ])
        
        parentView.addSubview(overlay)
        self.loadingOverlay = overlay
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.loadingOverlay != nil else { return }
            self.showLaunchFailure(targetURL: targetURL, reason: "Sau \(Int(self.launchTimeoutSeconds)) giây, WebKit chưa mở xong trang.")
        }
        self.launchTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + launchTimeoutSeconds, execute: workItem)
    }
    
    private func hideLaunchLoading() {
        launchTimeoutWorkItem?.cancel()
        launchTimeoutWorkItem = nil
        loadingOverlay?.removeFromSuperview()
        loadingOverlay = nil
        loadingLabel = nil
    }
    
    private func showLaunchFailure(targetURL: URL, reason: String) {
        hideLaunchLoading()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Chưa mở được trang thi"
        alert.informativeText = reason
        alert.addButton(withTitle: "Đóng")
        if let win = self.window {
            alert.window.level = NSWindow.Level(max(win.level.rawValue + 1, NSWindow.Level.modalPanel.rawValue))
        }
        alert.window.orderFrontRegardless()
        alert.runModal()
        showLauncher()
    }
    
    private func showBlockedNavigation(_ url: URL) {
        guard !blockedNavigationHandled else { return }
        blockedNavigationHandled = true
        
        let reason = DomainPolicy.blockedNavigationReason(for: url)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = reason.title
        alert.informativeText = reason.message
        alert.addButton(withTitle: "Thoát")
        if let win = self.window {
            alert.window.level = NSWindow.Level(max(win.level.rawValue + 1, NSWindow.Level.modalPanel.rawValue))
        }
        alert.window.orderFrontRegardless()
        alert.runModal()
        NSApp.terminate(nil)
    }
    
    // MARK: - Exit Confirmation Overlay
    
    private func requestExitConfirmation() {
        DispatchQueue.main.async { [weak self] in
            self?.presentExitConfirmation()
        }
    }
    
    private func presentExitConfirmation() {
        guard !exitConfirmationOpen, let parentView = window?.contentView else { return }
        exitConfirmationOpen = true
        exitConfirmationPreviousResponder = window?.firstResponder
        
        let overlay = NSView(frame: parentView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 14
        overlay.addSubview(card)
        
        let titleLabel = NSTextField(labelWithString: "Xác nhận thoát")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        card.addSubview(titleLabel)
        
        let messageLabel = NSTextField(labelWithString: "Bạn muốn thoát ứng dụng thi?")
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .systemFont(ofSize: 15, weight: .regular)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        card.addSubview(messageLabel)
        
        let stayButton = NSButton(title: "Ở lại", target: self, action: #selector(stayInApplicationFromOverlay(_:)))
        stayButton.translatesAutoresizingMaskIntoConstraints = false
        stayButton.bezelStyle = .rounded
        stayButton.keyEquivalent = "\r"
        stayButton.controlSize = .large
        card.addSubview(stayButton)
        
        let exitButton = NSButton(title: "Thoát", target: self, action: #selector(confirmExitFromOverlay(_:)))
        exitButton.translatesAutoresizingMaskIntoConstraints = false
        exitButton.bezelStyle = .rounded
        exitButton.controlSize = .large
        card.addSubview(exitButton)
        
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 340),
            card.heightAnchor.constraint(equalToConstant: 175),
            
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            
            stayButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 36),
            stayButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            stayButton.widthAnchor.constraint(equalToConstant: 120),
            
            exitButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -36),
            exitButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            exitButton.widthAnchor.constraint(equalToConstant: 120)
        ])
        
        parentView.addSubview(overlay)
        self.exitConfirmationOverlay = overlay
    }
    
    private func dismissExitConfirmation() {
        guard exitConfirmationOpen else { return }
        exitConfirmationOpen = false
        exitConfirmationOverlay?.removeFromSuperview()
        exitConfirmationOverlay = nil
        exitConfirmationPreviousResponder?.becomeFirstResponder()
    }
    
    @objc private func confirmExitFromOverlay(_ sender: Any?) {
        NSApp.terminate(nil)
    }
    
    @objc private func stayInApplicationFromOverlay(_ sender: Any?) {
        dismissExitConfirmation()
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        
        // Cho phép giao thức nội bộ về trang trống của WebKit (khi khởi động hoặc nạp launcher)
        if url.absoluteString == "about:blank" || url.scheme?.lowercased() == "about" {
            decisionHandler(.allow)
            return
        }
        
        if isShowingLauncher && url.scheme?.lowercased() == "file" {
            decisionHandler(.allow)
            return
        }
        
        if url.scheme?.lowercased() == "uthseb" {
            handleIncomingURL(url)
            decisionHandler(.cancel)
            return
        }
        
        // Cho phép các yêu cầu kết nối tới AI API / Gemini không bị chặn và không gắn hash header
        if AiMoodlePolicy.isAllowedAiURL(url) {
            decisionHandler(.allow)
            return
        }
        
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if !DomainPolicy.isAllowedWebURL(url) {
            if isMainFrame {
                showBlockedNavigation(url)
            }
            decisionHandler(.cancel)
            return
        }
        
        isShowingLauncher = false
        
        if !RequestAuthenticator.requestHasValidHash(navigationAction.request) {
            let signedRequest = RequestAuthenticator.addingHash(to: navigationAction.request)
            webView.load(signedRequest)
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if url.absoluteString == "about:blank" || url.scheme?.lowercased() == "about" {
                return nil
            }
            if AiMoodlePolicy.isAllowedAiURL(url) {
                webView.load(navigationAction.request)
            } else if DomainPolicy.isAllowedWebURL(url) {
                let signed = RequestAuthenticator.addingHash(to: navigationAction.request)
                webView.load(signed)
            } else {
                showBlockedNavigation(url)
            }
        }
        return nil
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        hideLaunchLoading()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideLaunchLoading()
        injectAiMoodleScript()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }
    
    private func handleNavigationFailure(_ error: Error) {
        hideLaunchLoading()
        if (error as NSError).code == NSURLErrorCancelled {
            return
        }
        if let target = currentLaunchTarget {
            showLaunchFailure(targetURL: target, reason: error.localizedDescription)
        }
    }
    
    // MARK: - WKScriptMessageHandler & AI Moodle Integration
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "uthseb" else { return }
        
        let dict: [String: Any]?
        if let d = message.body as? [String: Any] {
            dict = d
        } else if let str = message.body as? String,
                  let data = str.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            dict = json
        } else {
            dict = nil
        }
        
        guard let dict = dict, let type = dict["type"] as? String else { return }
        
        switch type {
        case "clipboardRequest":
            tryPasteClipboardToWebView()
            
        case "sessionValidated":
            sessionValidated = true
            
        case "licenseTokenSync":
            if let token = dict["token"] as? String, !token.isEmpty {
                saveCachedLicenseToken(token)
            }
            
        case "licenseRevoked":
            sessionValidated = false
            cachedLicenseToken = nil
            deleteCachedLicenseToken()
            
        case "apiCall":
            handleNativeApiCall(dict)
            
        default:
            break
        }
    }
    
    private func tryPasteClipboardToWebView() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard let jsonData = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        let script = "window.dispatchEvent(new MessageEvent('message', { data: { type: 'pasteData', text: \(jsonString) } }));"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    
    private func licenseFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("UTHSEB", isDirectory: true).appendingPathComponent("license_full.dat")
    }
    
    private func getCachedLicenseToken() -> String? {
        if let token = cachedLicenseToken, !token.isEmpty {
            return token
        }
        let file = licenseFileURL()
        if FileManager.default.fileExists(atPath: file.path),
           let data = try? Data(contentsOf: file),
           let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            cachedLicenseToken = token
            return token
        }
        return nil
    }
    
    private func saveCachedLicenseToken(_ token: String) {
        cachedLicenseToken = token
        let file = licenseFileURL()
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? token.write(to: file, atomically: true, encoding: .utf8)
    }
    
    private func deleteCachedLicenseToken() {
        sessionValidated = false
        cachedLicenseToken = nil
        let file = licenseFileURL()
        try? FileManager.default.removeItem(at: file)
        let legacyFile = file.deletingLastPathComponent().appendingPathComponent("license.dat")
        try? FileManager.default.removeItem(at: legacyFile)
    }
    
    private func loadAiMoodleScript() -> String? {
        // 1. Bundle.main resource
        if let url = Bundle.main.url(forResource: "AiMoodle", withExtension: "js"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        
        // 2. Resource Path
        if let resourcePath = Bundle.main.resourcePath {
            let path = (resourcePath as NSString).appendingPathComponent("AiMoodle.js")
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                return content
            }
            let subPath = (resourcePath as NSString).appendingPathComponent("Resources/AiMoodle.js")
            if let content = try? String(contentsOfFile: subPath, encoding: .utf8) {
                return content
            }
        }
        
        // 3. Executable and current directory fallbacks
        let exeURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let candidates = [
            exeURL.appendingPathComponent("Resources/AiMoodle.js"),
            exeURL.appendingPathComponent("Content/AiMoodle.js"),
            exeURL.appendingPathComponent("AiMoodle.js"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/AiMoodle.js")
        ]
        for candidate in candidates {
            if let content = try? String(contentsOf: candidate, encoding: .utf8) {
                return content
            }
        }
        
        return nil
    }
    
    private func injectAiMoodleScript() {
        let currentURL = webView?.url
        let isAllowed = currentURL.map { DomainPolicy.isAllowedWebURL($0) } ?? false
        let isLauncher = isShowingLauncher || currentURL == nil || currentURL?.absoluteString == "about:blank"
        guard isAllowed || isLauncher else {
            return
        }
        
        guard let script = loadAiMoodleScript() else {
            return
        }
        
        let cachedToken = getCachedLicenseToken()
        let tokenJSON: String
        if let token = cachedToken,
           let data = try? JSONSerialization.data(withJSONObject: token, options: [.fragmentsAllowed]),
           let str = String(data: data, encoding: .utf8) {
            tokenJSON = str
        } else {
            tokenJSON = "null"
        }
        
        let sessionValJSON = sessionValidated ? "true" : "false"
        let prelude = "window.__syncedLicenseToken = \(tokenJSON);\nwindow.__isSessionValidated = \(sessionValJSON);\n"
        
        webView?.evaluateJavaScript(prelude + script) { _, error in
            if let error = error {
                print("[UTHSEB] Lỗi evaluate AiMoodle script: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleNativeApiCall(_ dict: [String: Any]) {
        guard let reqId = dict["id"] as? String,
              let endpoint = dict["endpoint"] as? String else {
            return
        }
        
        let method = (dict["method"] as? String) ?? "GET"
        let customHeaders = (dict["headers"] as? [String: String]) ?? [:]
        let bodyString = dict["body"] as? String
        
        let baseURLString = "http://13.211.200.63:3000"
        guard let url = URL(string: baseURLString + endpoint) else {
            resolveNativeApiResponse(reqId: reqId, error: "URL không hợp lệ", statusCode: 0, responseText: "")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30.0
        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let bodyString = bodyString {
            request.httpBody = bodyString.data(using: .utf8)
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.resolveNativeApiResponse(reqId: reqId, error: error.localizedDescription, statusCode: 0, responseText: "")
                    return
                }
                
                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? 200
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                
                self?.resolveNativeApiResponse(reqId: reqId, error: nil, statusCode: statusCode, responseText: text)
            }
        }.resume()
    }
    
    private func resolveNativeApiResponse(reqId: String, error: String?, statusCode: Int, responseText: String) {
        let errorJSON: String
        if let error = error,
           let data = try? JSONSerialization.data(withJSONObject: error, options: [.fragmentsAllowed]),
           let str = String(data: data, encoding: .utf8) {
            errorJSON = str
        } else {
            errorJSON = "null"
        }
        
        let textJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: responseText, options: [.fragmentsAllowed]),
           let str = String(data: data, encoding: .utf8) {
            textJSON = str
        } else {
            textJSON = "\"\""
        }
        
        let script = "if (typeof window.__handleNativeApiResponse === 'function') { window.__handleNativeApiResponse(\"\(reqId)\", \(errorJSON), \(statusCode), \(textJSON)); }"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
}
