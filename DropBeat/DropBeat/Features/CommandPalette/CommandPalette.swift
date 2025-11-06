import SwiftUI
import AppKit

@MainActor
final class CommandPalette: NSObject {
    static let shared = CommandPalette()
    private var window: NSPanel?
    private let state = CommandPaletteState.shared
    private let wsManager = WebSocketManager.shared
    private var mouseEventTap: CFMachPort?

    private override init() {
        super.init()
        setupWindow()
    }
    
    private func setupWindow() {
        // DESIGN: Adjust window size (width: 800, height: 400)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.backgroundColor = .clear // DESIGN: Background color for transparent window
        window.isOpaque = false // DESIGN: Allows transparency
        window.hasShadow = true // DESIGN: Add/remove drop shadow
        window.isMovable = false // DESIGN: Set to true to make window draggable
        window.hidesOnDeactivate = false // DESIGN: Keep visible when app loses focus
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        
        window.delegate = self
        
        let hostingView = NSHostingView(rootView: CommandPaletteView())
        window.contentView = hostingView
        
        self.window = window
    }
    
    nonisolated
    func toggle() {
        Task { @MainActor in
            if state.isVisible {
                await hide()
            } else {
                await show()
            }
        }
    }
    
    private func show() {
        guard let window = window else { return }

        // Mark as visible FIRST before anything else
        state.isVisible = true

        // Center window on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame

            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2 + (screenFrame.height * 0.1)

            window.setFrame(NSRect(
                x: x,
                y: y,
                width: windowFrame.width,
                height: windowFrame.height
            ), display: true)
        }

        // Aggressive window activation to make it prominent
        // This ensures the window appears above all other windows including fullscreen apps
        window.level = .statusBar // Higher than .floating to ensure visibility over fullscreen content
        NSApp.activate(ignoringOtherApps: true)
        print("🎯 [palette] Making window key and ordered front (initial)")
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Multiple activation attempts to ensure focus reaches the window
        DispatchQueue.main.async {
            print("🎯 [palette] Async activation attempt 1")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            window.makeKeyAndOrderFront(nil)
        }

        // Additional attempt after a brief delay to overcome fullscreen app focus hogging
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            print("🎯 [palette] Async activation attempt 2 at +50ms")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        // Ensure window stays visible across all spaces by enabling the proper collection behaviors
        if #available(macOS 12.0, *) {
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        }

        // Signal to the view that the window is now visible and ready for input
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("CommandPaletteWillShow"), object: nil)
        }

        // Setup mouse event tap to detect clicks outside the window
        setupMouseEventTap()

        // Send refresh command to content script
        Task {
            do {
                try await wsManager.send(command: "COMMAND_PALETTE_OPENED")
                print("✅ [dropbeats] Sent command palette refresh command")
            } catch {
                print("❌ [dropbeats] Failed to send command palette refresh command:", error)
            }
        }
    }
    
    private func hide() {
        print("🎯 [palette] Hiding palette")
        // Cleanup mouse event tap
        cleanupMouseEventTap()
        window?.orderOut(nil)
        state.isVisible = false
        state.searchText = ""
    }

    private func setupMouseEventTap() {
        print("🎯 [palette] Setting up mouse event tap for click-outside detection")
        guard let paletteWindow = window else { return }

        // Store window frame for callback reference
        let windowFrame = paletteWindow.frame

        // Create mouse event tap to detect clicks outside the palette window
        let eventMask = CGEventMask((1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue))

        // Create a callback that checks if click is inside window
        let mouseEventCallback: @convention(c) (CGEventTapProxy, CGEventType, CGEvent, UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? = { proxy, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }

            // Retrieve the palette pointer and window frame
            let palettePointer = Unmanaged<CommandPalette>.fromOpaque(userInfo).takeUnretainedValue()

            // Get the click location (in screen coordinates)
            let location = event.location

            // Get the palette window's current frame
            guard let currentWindow = palettePointer.window else {
                return Unmanaged.passRetained(event)
            }

            // Check if click is inside the palette window
            if currentWindow.frame.contains(location) {
                // Click inside palette - let it through
                return Unmanaged.passRetained(event)
            } else {
                // Click outside palette - close it
                print("🎯 [palette] Click detected outside palette at \(location) vs window \(currentWindow.frame)")
                Task { @MainActor in
                    await palettePointer.hide()
                }
                return Unmanaged.passRetained(event)
            }
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: mouseEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ [palette] Failed to create mouse event tap")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        mouseEventTap = eventTap
        print("🎯 [palette] Mouse event tap installed")
    }

    private func cleanupMouseEventTap() {
        print("🎯 [palette] Cleaning up mouse event tap")
        if let eventTap = mouseEventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            mouseEventTap = nil
        }
    }
}

// MARK: - NSWindowDelegate
extension CommandPalette: NSWindowDelegate {
    nonisolated
    func windowDidResignKey(_ notification: Notification) {
        // CRITICAL: Don't auto-hide! Using CGEventTap means hotkey is triggered at OS level
        // Window should stay visible until user dismisses with Escape or clicks outside
        // Auto-hiding here causes the "flashing" issue when switching between fullscreen apps
        // Task { @MainActor in
        //     await hide()
        // }
    }

    nonisolated
    func windowDidResignMain(_ notification: Notification) {
        // CRITICAL: Same - don't auto-hide
        // Task { @MainActor in
        //     await hide()
        // }
    }
} 
