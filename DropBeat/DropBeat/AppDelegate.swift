import Foundation
import SwiftUI
import AppKit
import Network
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var wsManager: WebSocketManager
    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 0)
        popover.behavior = .transient
        
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
    
    override init() {
        self.wsManager = WebSocketManager.shared
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize AppStateManager
        AppStateManager.shared.initialize()
        
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
        
        // Setup keyboard shortcuts after checking license
        setupKeyboardShortcuts()
        
        // Check if we need to show onboarding
        Task {
            await checkAndShowOnboarding()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup timer
        serverKeepAlive?.cleanup()
        
        // Your existing cleanup code...
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
            self.wsManager.togglePlayPause()
            self.showNotification(icon: "playpause.fill", text: "Music Play / Pause")
        }
        
        KeyboardShortcuts.onKeyDown(for: .nextTrack) { [weak self] in
            guard let self = self else { return }
            self.wsManager.next()
            self.showNotification(icon: "forward.fill", text: "Next Music")
        }
        
        KeyboardShortcuts.onKeyDown(for: .previousTrack) { [weak self] in
            guard let self = self else { return }
            self.wsManager.previous()
            self.showNotification(icon: "backward.fill", text: "Previous Music")
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
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        updateMenu()
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        // Now Playing Section
        if let currentTrack = wsManager.currentTrack {
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
            title: wsManager.currentTrack?.isPlaying == true ? "Pause" : "Play",
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
        
        // Connection Status
        let statusItem = NSMenuItem()
        statusItem.title = wsManager.isConnected ? "Connected" : "Disconnected"
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit DropBeat",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                // Create a zero-origin rect that maintains the button's size
                let rect = NSRect(x: -120, y: 0, width: 280, height: button.bounds.height)
                popover.show(relativeTo: rect, of: button, preferredEdge: .minY)
            }
        }
    }
    
    @objc func handleConnectionChange() {
        if wsManager.isConnected {
            statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "DropBeat")
        } else {
            // Using a more appropriate disconnected icon
            if let disconnectedIcon = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "DropBeat Disconnected") {
                statusItem.button?.image = disconnectedIcon
            } else {
                statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "DropBeat")
            }
        }
        updateMenu()
    }
    
    @objc func handleTrackChange() {
        updateMenu()
    }
    
    @objc func togglePlayPause() {
        wsManager.togglePlayPause()
    }
    
    @objc func previousTrack() {
        wsManager.previous()
    }
    
    @objc func nextTrack() {
        wsManager.next()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }
    
    @objc private func handleShowOnboarding() {
        // Close any open windows/popovers
        if popover.isShown {
            popover.performClose(nil)
        }
        
        // Show onboarding
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
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        
        // Keep a reference to prevent deallocation
        self.onboardingWindow = window
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
}

