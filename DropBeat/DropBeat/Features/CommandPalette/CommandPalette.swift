import SwiftUI
import AppKit

// Custom NSPanel that can always become key window for proper keyboard focus
class AlwaysKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class CommandPalette: NSObject {
    static let shared = CommandPalette()
    private var window: NSPanel?
    private let state = CommandPaletteState.shared
    private var mouseEventMonitor: Any?

    private override init() {
        super.init()
        setupWindow()
    }
    
    private func setupWindow() {
        // DESIGN: Adjust window size (width: 800, height: 400)
        // Use custom NSPanel subclass that can always become key window
        let window = AlwaysKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Use higher window level for better visibility over all apps
        window.level = .popUpMenu  // Higher than .floating, works better for popovers
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
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

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
        // Mirror for the event-tap thread, which must never block on the main
        // actor to read this. Kept beside the assignment rather than in a
        // didSet, because @Observable rewrites stored properties and property
        // observers do not survive the macro.
        PaletteVisibility.isVisible = true

        // Re-assert Space and level behaviour on every show, not just once at
        // construction. The window is built at launch and reused forever; after
        // orderOut/orderFront cycles — especially across a full-screen Space
        // transition — macOS does not reliably keep the original association,
        // and the panel ends up bound to whichever Space it was last shown on.
        // That is the "it sticks to one window" symptom.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.level = .popUpMenu

        // Place on the screen the POINTER is on, not NSScreen.main.
        //
        // NSScreen.main means "the screen with the key window". A menu-bar app
        // with no key window has no meaningful answer, so on a multi-display
        // setup this could centre the palette on a display you are not looking
        // at — indistinguishable, from the user's side, from it not opening.
        let targetScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let screen = targetScreen {
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

        // Deliberately NOT calling NSApp.activate(ignoringOtherApps:).
        //
        // It contradicts .nonactivatingPanel, and over a full-screen app it is
        // actively harmful: activating an accessory app can make macOS switch
        // Spaces to wherever the app "lives", yanking the user out of their
        // full-screen window. .fullScreenAuxiliary exists precisely so a panel
        // can join the current full-screen Space WITHOUT an app switch, and
        // forcing activation defeats it.
        //
        // Keyboard focus does not depend on activation here: AlwaysKeyPanel
        // overrides canBecomeKey, which is what lets a non-activating panel
        // take key status while the app underneath stays active. This is how
        // Spotlight-style panels behave.
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        print("🎯 [palette] Window shown on \(targetScreen?.localizedName ?? "unknown screen")")

        // Signal to the view that the window is now visible and ready for input
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NSNotification.Name("CommandPaletteWillShow"), object: nil)
        }

        // Setup mouse event tap to detect clicks outside the window
        setupMouseEventTap()
    }
    
    private func hide() {
        print("🎯 [palette] Hiding palette")
        // Cleanup mouse event tap
        cleanupMouseEventTap()
        window?.orderOut(nil)
        state.isVisible = false
        PaletteVisibility.isVisible = false
        state.searchText = ""
    }

    private func setupMouseEventTap() {
        print("🎯 [palette] Setting up global mouse event monitor for click-outside detection")
        guard let paletteWindow = window else { return }

        // Use NSEvent GLOBAL monitor to detect clicks anywhere (no accessibility required)
        // Global monitor can't modify events but can detect them from all windows
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }

            // Check if palette is visible
            guard self.state.isVisible, let currentWindow = self.window else {
                print("🎯 [palette] Global monitor: palette not visible")
                return
            }

            print("🎯 [palette] Global mouse click detected")

            // Get the click location in screen coordinates
            let clickLocation = NSEvent.mouseLocation
            let windowFrame = currentWindow.frame

            print("🎯 [palette] Window frame: \(windowFrame), Click location: \(clickLocation)")

            // Check if click is inside the palette window
            if windowFrame.contains(clickLocation) {
                // Click inside palette - do nothing
                print("🎯 [palette] Click INSIDE palette - ignoring")
            } else {
                // Click outside palette - close it
                print("🎯 [palette] Click OUTSIDE palette at \(clickLocation) - closing")
                Task { @MainActor in
                    print("🎯 [palette] Calling hide from global mouse event monitor")
                    await self.hide()
                }
            }
        }

        mouseEventMonitor = monitor
        print("🎯 [palette] Global mouse event monitor installed")
    }

    private func cleanupMouseEventTap() {
        print("🎯 [palette] Cleaning up mouse event monitor")
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
            mouseEventMonitor = nil
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
