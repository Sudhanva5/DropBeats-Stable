import Foundation
import SwiftUI
import AppKit
import Network
import KeyboardShortcuts
import CoreGraphics
import Accessibility

// MARK: - Global Event Tap for Command Palette Hotkey
// This allows the hotkey to work over fullscreen apps by intercepting at OS level
var globalEventTap: CFMachPort?
var globalEventTapSource: CFRunLoopSource?

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // Check if this is a key down event
    guard type == .keyDown else { return Unmanaged.passRetained(event) }

    // Get the key code
    let keyCode = Int64(event.getIntegerValueField(.keyboardEventKeycode))

    // Get modifier flags
    let flags = event.flags

    // Cmd+Option+Space = Cmd (1048576) + Option (524288) + Space (49)
    // Check for Command (0x100000) + Option (0x80000) + Space keycode (49)
    let hasCmdModifier = flags.rawValue & 0x100000 != 0
    let hasOptModifier = flags.rawValue & 0x80000 != 0
    let isSpaceKey = keyCode == 49

    if hasCmdModifier && hasOptModifier && isSpaceKey {
        print("🎹 [palette] Command Palette hotkey detected at OS level (fullscreen compatible)")

        // Show command palette
        Task { @MainActor in
            await CommandPalette.shared.toggle()
        }

        // Consume the event so the fullscreen app doesn't see it
        return nil
    }

    // If palette is visible, handle keyboard input for it
    // NOTE: eventTapCallback runs on a non-main thread, so we need to check main-actor properties safely
    var paletteVisible = false
    let semaphore = DispatchSemaphore(value: 0)

    DispatchQueue.main.async {
        paletteVisible = CommandPaletteState.shared.isVisible
        semaphore.signal()
    }
    semaphore.wait()

    if paletteVisible {
        // Escape key (keyCode 53) - dismiss palette
        if keyCode == 53 {
            print("🎹 [palette] Escape key pressed - dismissing palette")
            Task { @MainActor in
                await CommandPalette.shared.toggle()
            }
            return nil  // Consume the Escape key
        }

        // Return/Enter key (keyCode 36) - handled by view, pass through
        // Delete/Backspace (keyCode 51) - pass through
        // Arrow keys (keyCode 123-126) - pass through
        // Command key combinations - pass through

        // All other keyboard input: pass through to palette window
        // The palette's search field can receive input even without window focus
        // when text is passed through the event system

        // For text input keys, we need to ensure the palette window is active
        let isTextInput = !(flags.rawValue & 0x100000 != 0) && // Not command
                         !(flags.rawValue & 0x80000 != 0)     // Not option

        if isTextInput || keyCode == 36 || keyCode == 51 || (keyCode >= 123 && keyCode <= 126) {
            // Reinforce that palette should be in focus for these important keys
            if isTextInput {
                print("📝 [palette] Feeding text input to palette (keyCode: \(keyCode))")
            }
        }

        return Unmanaged.passRetained(event)
    }

    // When palette is not visible, let all events pass through
    return Unmanaged.passRetained(event)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var contextMenu: NSMenu?
    private var playerManager: MusicPlayerManager
    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 0)
        // Use .applicationDefined to allow interaction without auto-closing
        // We'll manually handle closing via click-outside detection
        popover.behavior = .applicationDefined

        // Create a container view controller to handle the padding
        let contentViewController = NSHostingController(rootView: ContentView())
        contentViewController.view.wantsLayer = true

        popover.contentViewController = contentViewController
        popover.delegate = self
        return popover
    }()
    private var popoverMonitor: Any?
    private var hudWindow: NSWindow?
    private var serverKeepAlive: SearchServerKeepAlive?
    var onboardingWindow: NSWindow?
    private var eventTapMonitorTimer: Timer?
    
    override init() {
        self.playerManager = MusicPlayerManager.shared
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize AppStateManager
        AppStateManager.shared.initialize()

        // Start local backend server (required for yt-dlp stream URLs)
        print("🚀 [DropBeats] Starting local backend server...")
        BackendServerManager.shared.startServer { success in
            if success {
                print("✅ [DropBeats] Backend server is ready!")
                BackendConfig.printConfig()
            } else {
                print("⚠️ [DropBeats] Backend server failed to start - app may not function correctly")
            }
        }

        // Initialize server keep-alive
        serverKeepAlive = SearchServerKeepAlive.shared

        // Always use accessory mode (menu bar only)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup menu bar and observe license status
        setupMenuBar()
        
        // Observe license status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLicenseStatusChange),
            name: NSNotification.Name("LicenseStatusChanged"),
            object: nil
        )
        
        // Observe onboarding state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOnboardingStateChange),
            name: NSNotification.Name("OnboardingStateChanged"),
            object: nil
        )
        
        // Observe WebSocket connection changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConnectionChange),
            name: NSNotification.Name("WebSocketConnectionChanged"),
            object: nil
        )
        
        // Observe track changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTrackChange),
            name: NSNotification.Name("TrackChanged"),
            object: nil
        )
        
        // Observe forced onboarding
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowOnboarding),
            name: NSNotification.Name("ShowOnboarding"),
            object: nil
        )

        // Observe onboarding completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloseOnboarding),
            name: NSNotification.Name("CloseOnboarding"),
            object: nil
        )
        
        // Setup keyboard shortcuts after checking license
        setupKeyboardShortcuts()

        // Setup global event tap for command palette hotkey (works over fullscreen apps)
        setupGlobalEventTap()

        // Check if we need to show onboarding
        Task {
            await checkAndShowOnboarding()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Stop local backend server
        print("🛑 [DropBeats] Shutting down backend server...")
        BackendServerManager.shared.stopServer()

        // Cleanup timers
        serverKeepAlive?.cleanup()
        eventTapMonitorTimer?.invalidate()
        eventTapMonitorTimer = nil
    }
    
    private func setupKeyboardShortcuts() {
        // Only setup shortcuts if license is valid
        guard case .valid = AppStateManager.shared.licenseStatus else {
            return
        }
        
        KeyboardShortcuts.onKeyDown(for: .toggleCommandPalette) { [weak self] in
            Task { @MainActor in
                await CommandPalette.shared.toggle()
            }
        }
        
        KeyboardShortcuts.onKeyDown(for: .togglePlayPause) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.playerManager.togglePlayPause()
                self.showNotification(icon: "playpause.fill", text: "Music Play / Pause")
            }
        }

        KeyboardShortcuts.onKeyDown(for: .nextTrack) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.playerManager.next()
                self.showNotification(icon: "forward.fill", text: "Next Music")
            }
        }

        KeyboardShortcuts.onKeyDown(for: .previousTrack) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.playerManager.previous()
                self.showNotification(icon: "backward.fill", text: "Previous Music")
            }
        }
    }

    private func setupGlobalEventTap() {
        print("🔍 [palette] Checking accessibility permissions...")

        // Check accessibility permissions without prompting (onboarding handles permission requests)
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        print("🔍 [palette] AXIsProcessTrustedWithOptions returned: \(accessibilityEnabled)")

        guard accessibilityEnabled else {
            print("⚠️ [palette] Accessibility permissions not granted - command palette hotkey won't work over fullscreen apps")
            print("   Please grant DropBeat accessibility permissions in System Preferences > Security & Privacy > Accessibility")
            return
        }

        print("✅ [palette] Accessibility permissions granted - setting up global event tap")

        // Create event tap for keyboard events
        let eventMask = CGEventMask((1 << CGEventType.keyDown.rawValue))

        print("🔍 [palette] Creating event tap with session-level tap for fullscreen compatibility...")

        // Use .cgSessionEventTap for better fullscreen app compatibility
        // This allows the event tap to work even when fullscreen apps are active
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            print("❌ [palette] Failed to create event tap")
            return
        }

        print("🔍 [palette] Event tap created, creating run loop source...")

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        globalEventTap = eventTap
        globalEventTapSource = runLoopSource

        print("🎹 [palette] Global event tap installed - Cmd+Option+Space will work over fullscreen apps")

        // Start monitoring the event tap to detect when macOS disables it
        startEventTapMonitoring()
    }

    /// Monitor event tap and re-enable if macOS disables it
    private func startEventTapMonitoring() {
        // Cancel existing timer if any
        eventTapMonitorTimer?.invalidate()

        // Check event tap status every 5 seconds
        eventTapMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkAndRestoreEventTap()
        }

        print("👁️ [palette] Event tap monitoring started")
    }

    /// Check if event tap is still enabled and re-enable if necessary
    private func checkAndRestoreEventTap() {
        guard let eventTap = globalEventTap else { return }

        // Check if event tap is still enabled
        let isEnabled = CFMachPortIsValid(eventTap)

        if !isEnabled {
            print("⚠️ [palette] Event tap was disabled by macOS - attempting to restore...")

            // Re-enable the event tap
            CGEvent.tapEnable(tap: eventTap, enable: true)

            // Verify it's enabled now
            if CFMachPortIsValid(eventTap) {
                print("✅ [palette] Event tap successfully restored")
            } else {
                print("❌ [palette] Failed to restore event tap - recreating...")
                // If re-enabling failed, recreate the entire event tap
                setupGlobalEventTap()
            }
        }
    }

    private func showNotification(icon: String, text: String) {
        // Cleanup existing
        hudWindow?.close()
        
        // Create simple HUD window
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Create HUD view
        let hudView = NSVisualEffectView(frame: window.contentView!.bounds)
        hudView.material = .hudWindow
        hudView.state = .active
        hudView.wantsLayer = true
        hudView.layer?.cornerRadius = 20
        
        // Icon
        let imageView = NSImageView(frame: NSRect(x: 60, y: 80, width: 54, height: 54))
        imageView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 50, weight: .regular))
        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = .secondaryLabelColor
        
        // Label
        let label = NSTextField(frame: NSRect(x: 0, y: 48, width: 180, height: 20))
        label.stringValue = text
        label.alignment = .center
        label.font = .systemFont(ofSize: 16)
        label.textColor = .labelColor
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        
        hudView.addSubview(imageView)
        hudView.addSubview(label)
        window.contentView = hudView
        
        // Center and moved slightly to the bottom of the screen
        if let screen = NSScreen.main {
            let x = screen.frame.midX - 100
            let y = screen.frame.midY - 300
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        hudWindow = window
        window.orderFront(nil)
        
        // Fade in
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            window.animator().alphaValue = 1
        }
        
        // Auto dismiss with fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                window.animator().alphaValue = 0
            } completionHandler: {
                window.close()
                self.hudWindow = nil
            }
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "DropBeats")
            button.action = #selector(handleStatusBarClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        updateMenu()
    }

    @objc private func handleStatusBarClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right-click: show context menu
            if let button = statusItem.button, let menu = contextMenu {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
            }
        } else {
            // Left-click: show popover
            togglePopover()
        }
    }
    
    private func updateMenu() {
        Task { @MainActor in
            let menu = NSMenu()

            // Now Playing Section
            if let currentTrack = playerManager.currentTrack {
                let nowPlayingItem = NSMenuItem()
                nowPlayingItem.title = "Now Playing: \(currentTrack.title)"
                nowPlayingItem.isEnabled = false
                menu.addItem(nowPlayingItem)

                let artistItem = NSMenuItem()
                artistItem.title = "By \(currentTrack.artist)"
                artistItem.isEnabled = false
                menu.addItem(artistItem)

                menu.addItem(NSMenuItem.separator())
            }

            // Playback Controls
            let playPauseItem = NSMenuItem(
                title: playerManager.isPlaying ? "Pause" : "Play",
                action: #selector(togglePlayPause),
                keyEquivalent: "p"
            )
                menu.addItem(playPauseItem)

            let previousItem = NSMenuItem(
                title: "Previous",
                action: #selector(previousTrack),
                keyEquivalent: "["
            )
            menu.addItem(previousItem)

            let nextItem = NSMenuItem(
                title: "Next",
                action: #selector(nextTrack),
                keyEquivalent: "]"
            )
            menu.addItem(nextItem)

            menu.addItem(NSMenuItem.separator())

            // Quit
            let quitItem = NSMenuItem(
                title: "Quit DropBeat",
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
            menu.addItem(quitItem)

            // Store menu separately - don't set statusItem.menu or it overrides button action
            self.contextMenu = menu
        }
    }
    
    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                closePopover()
            } else {
                // Activate app first to ensure proper focus
                NSApp.activate(ignoringOtherApps: true)

                // Create a zero-origin rect that maintains the button's size
                let rect = NSRect(x: -120, y: 0, width: 280, height: button.bounds.height)
                popover.show(relativeTo: rect, of: button, preferredEdge: .minY)

                // Setup click-outside detection to close popover (like system menu bar items)
                setupPopoverMonitor()
            }
        }
    }

    private func setupPopoverMonitor() {
        // Remove any existing monitor
        if let monitor = popoverMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Monitor for clicks outside the popover
        popoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            if self.popover.isShown {
                self.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)

        // Remove the event monitor
        if let monitor = popoverMonitor {
            NSEvent.removeMonitor(monitor)
            popoverMonitor = nil
        }
    }
    
    @objc func handleConnectionChange() {
        // No longer needed (no Chrome Extension dependency)
        updateMenu()
    }
    
    @objc func handleTrackChange() {
        updateMenu()
    }
    
    @objc func togglePlayPause() {
        Task { @MainActor in
            playerManager.togglePlayPause()
        }
    }

    @objc func previousTrack() {
        Task { @MainActor in
            playerManager.previous()
        }
    }

    @objc func nextTrack() {
        Task { @MainActor in
            playerManager.next()
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }
    
    @objc private func handleShowOnboarding() {
        print("🎯 [dropbeats] ShowOnboarding notification received")

        // Close any open windows/popovers
        if popover.isShown {
            print("🎯 [dropbeats] Closing popover")
            popover.performClose(nil)
        }

        // Show onboarding
        print("🎯 [dropbeats] Calling showOnboarding()")
        showOnboarding()
    }
    
    private func checkAndShowOnboarding() async {
        // Check if there's a stored license key and validate it
        if let storedKey = UserDefaults.standard.string(forKey: "licenseKey") {
            do {
                let response = try await LicenseService.shared.validateLicense(key: storedKey)
                await MainActor.run {
                    if !response.valid || response.hasCompletedOnboarding == false {
                        // If license is invalid or onboarding not completed, show onboarding
                        UserDefaults.standard.removeObject(forKey: "licenseKey")
                        showOnboarding()
                    }
                }
            } catch {
                // If validation fails, show onboarding
                await MainActor.run {
                    showOnboarding()
                }
            }
        } else {
            // No license key found, show onboarding
            await MainActor.run {
                showOnboarding()
            }
        }
    }
    
    private func showOnboarding() {
        // If onboarding window already exists, just bring it to front
        if let existingWindow = onboardingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Welcome to DropBeat"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.level = .normal  // Use normal level so system permission dialogs appear above
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print("🎯 [dropbeats] Onboarding window shown")

        // Keep a reference to prevent deallocation
        self.onboardingWindow = window
    }

    @objc private func handleCloseOnboarding() {
        print("🎯 [dropbeats] CloseOnboarding notification received")

        if let window = onboardingWindow {
            window.close()
            onboardingWindow = nil
            print("🎯 [dropbeats] Onboarding window closed")
        }
    }
    
    @objc private func handleLicenseStatusChange() {
        updateMenu()
        // Re-setup keyboard shortcuts based on license status
        setupKeyboardShortcuts()
    }
    
    @objc private func handleOnboardingStateChange(_ notification: Notification) {
        updateMenu()
    }
    
    private func enableAppFunctionality() {
        updateMenu()
        setupKeyboardShortcuts()
    }
    
    private func disableAppFunctionality() {
        updateMenu()
    }
}

// MARK: - NSPopoverDelegate
extension AppDelegate: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        if let popoverWindow = popover.contentViewController?.view.window {
            // Set window level to stay visible over full-screen apps
            popoverWindow.level = .popUpMenu
        }
    }

    func popoverDidClose(_ notification: Notification) {
        // Clean up event monitor when popover closes
        if let monitor = popoverMonitor {
            NSEvent.removeMonitor(monitor)
            popoverMonitor = nil
        }
    }
}

