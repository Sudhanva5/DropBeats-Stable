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
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
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
            ), display: false)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        state.isVisible = true
        
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
        Task { @MainActor in
            await hide()
        }
    }
    
    nonisolated
    func windowDidResignMain(_ notification: Notification) {
        Task { @MainActor in
            await hide()
        }
    }
} 