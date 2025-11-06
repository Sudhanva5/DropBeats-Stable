import SwiftUI
import AppKit

@MainActor
final class CommandPalette: NSObject {
    static let shared = CommandPalette()
    private var window: NSPanel?
    private let state = CommandPaletteState.shared
    private let wsManager = WebSocketManager.shared
    
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

        // Send refresh command to content script
        Task {
            do {
                try await wsManager.send(command: "COMMAND_PALETTE_OPENED")
                print("✅ [DropBeat] Sent command palette refresh command")
            } catch {
                print("❌ [DropBeat] Failed to send command palette refresh command:", error)
            }
        }
    }
    
    private func hide() {
        window?.orderOut(nil)
        state.isVisible = false
        state.searchText = ""
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
