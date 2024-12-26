import Foundation
import SwiftUI
import AppKit
import Network
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var wsManager: WebSocketManager
    private var popover: NSPopover!
    private var popoverMonitor: Any?
    
    override init() {
        self.wsManager = WebSocketManager.shared
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        setupMenuBar()
        setupPopover()
        setupKeyboardShortcuts()
        
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
    }
    
    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .toggleCommandPalette) { [weak self] in
            Task { @MainActor in
                await CommandPalette.shared.toggle()
            }
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "DropBeat")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        updateMenu()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 0)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())
        popover.delegate = self
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
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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

