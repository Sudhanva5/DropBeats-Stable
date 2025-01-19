import SwiftUI
import AppKit

@main
struct DropBeatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified)
        .windowLevel(.floating)
    }
}

