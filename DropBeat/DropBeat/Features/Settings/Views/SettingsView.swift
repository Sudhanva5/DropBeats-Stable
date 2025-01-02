import SwiftUI
import AppKit
import KeyboardShortcuts

// MARK: - Main Settings View
struct SettingsView: View {
    // Customize the width of the settings window here
    private let settingsWidth: CGFloat = 580
    
    var body: some View {
        TabView {
            GeneralTabView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            ShortcutsTabView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
            
            AboutTabView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: settingsWidth)
        .background(EffectView(material: .contentBackground))
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            setupGlobalShortcuts()
        }
    }
    
    private func setupGlobalShortcuts() {
        // Command Search
        KeyboardShortcuts.onKeyDown(for: .toggleCommandPalette) {
            print("Open Command Search")
            // TODO: Implement command search
        }
        
        // Play/Pause
        KeyboardShortcuts.onKeyDown(for: .togglePlayPause) {
            print("Play/Pause Music")
            // TODO: Implement play/pause
        }
        
        // Next Track
        KeyboardShortcuts.onKeyDown(for: .nextTrack) {
            print("Next Music")
            // TODO: Implement next
        }
        
        // Previous Track
        KeyboardShortcuts.onKeyDown(for: .previousTrack) {
            print("Previous Music")
            // TODO: Implement previous
        }
    }
}

struct EffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

// MARK: - General Tab
struct GeneralTabView: View {
    @State private var startAtLogin: Bool = false
    @State private var showDockIcon: Bool = true
    @StateObject private var cardRef = AccessCardViewModel()
    @State private var isHovering: String? = nil
    
    // Constants for layout - matching AccessCardView's dimensions
    private let cardWidth: CGFloat = 260
    private let leftSectionWidth: CGFloat = 280
    private let sectionSpacing: CGFloat = 0
    private let buttonSpacing: CGFloat = 16
    
    var body: some View {
        HStack(alignment: .top, spacing: sectionSpacing) {
            // Left Section - Access Card
            VStack(spacing: 20) {
                AccessCardView()
                    .environmentObject(cardRef)
                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                
                // Action Buttons
                HStack(spacing: buttonSpacing) {
                    ActionButton(
                        icon: "square.and.arrow.down",
                        isHovering: isHovering == "download",
                        action: { _ in
                            // Create a hosting view for the access card with 4x scale for better quality
                            let scale: CGFloat = 4.0  // Increased scale for better quality
                            let hostingView = NSHostingView(rootView: AccessCardView()
                                .environmentObject(cardRef)
                                .frame(width: 260, height: 340))
                            
                            // Set up the hosting view with high-quality rendering
                            hostingView.frame = CGRect(x: 0, y: 0, width: 260 * scale, height: 340 * scale)
                            hostingView.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
                            hostingView.wantsLayer = true
                            
                            // Allow the view to render
                            hostingView.layoutSubtreeIfNeeded()
                            
                            let bitmap = hostingView.bitmapImage()
                            
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = "DropBeats-Access-Card.png"
                            panel.begin { response in
                                if response == .OK {
                                    if let url = panel.url {
                                        if let pngData = bitmap.tiffRepresentation,
                                           let bitmapRep = NSBitmapImageRep(data: pngData) {
                                            bitmapRep.size = NSSize(width: 260 * scale, height: 340 * scale)
                                            if let data = bitmapRep.representation(using: .png, properties: [
                                                .compressionFactor: 1.0,
                                                .interlaced: false
                                            ]) {
                                                try? data.write(to: url)
                                            }
                                        }
                                    }
                                }
                            }
                        },
                        onHover: { hovering in
                            isHovering = hovering ? "download" : nil
                        }
                    )
                    .help("Download Access Card")
                    
                    ActionButton(
                        icon: "square.and.arrow.up",
                        isHovering: isHovering == "share",
                        action: { view in
                            let sharingText = "Check out DropBeats - my favorite YouTube Music companion! It helps me stay focused while working by providing seamless music controls. Try it out!"
                            let picker = NSSharingServicePicker(items: [sharingText])
                            
                            // Get the actual button view and show picker above it
                            if let buttonView = view {
                                let rect = NSRect(x: 0, y: buttonView.bounds.height, width: buttonView.bounds.width, height: 0)
                                picker.show(relativeTo: rect, of: buttonView, preferredEdge: .maxY)
                            }
                        },
                        onHover: { hovering in
                            isHovering = hovering ? "share" : nil
                        }
                    )
                    .help("Share DropBeat")
                    
                    ActionButton(
                        icon: "dice",
                        isHovering: isHovering == "randomize",
                        action: { _ in
                            withAnimation {
                                cardRef.randomizeTheme()
                            }
                        },
                        onHover: { hovering in
                            isHovering = hovering ? "randomize" : nil
                        }
                    )
                    .help("Randomize Theme")
                }
            }
            .frame(width: leftSectionWidth)
            
            // Right Section - Settings
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        LicenseInfoRow(title: "Account", value: "sudhanva.udupi55@gmail.com")
                        LicenseInfoRow(title: "Validity", value: "Lifetime")
                        LicenseInfoRow(title: "License", value: "DB-2024-WEXS")
                        LicenseInfoRow(title: "Member Since", value: "January 2024")
                    }
                } header: {
                    Text("License Information")
                        .font(.headline)
                        .padding(.leading, -8)
                }
                
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Start at login", isOn: $startAtLogin)
                            .help("Launch DropBeat automatically when you log in")
                        
                        Toggle("Show dock icon", isOn: $showDockIcon)
                            .help("Show DropBeat icon in the Dock")
                    }
                } header: {
                    Text("App Settings")
                        .font(.headline)
                        .padding(.leading, -8)
                }
            }
            .transparentGroupedForm()
        }
        .padding()
    }
}

struct ActionButton: View {
    let icon: String
    let isHovering: Bool
    let action: (NSView?) -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        Button {
            let view = NSApp.keyWindow?.contentView?.hitTest(NSEvent.mouseLocation)
            action(view)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color(.controlBackgroundColor) : Color.clear)
                        .shadow(color: isHovering ? .black.opacity(0.1) : .clear, radius: 1, x: 0, y: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }
}

// Update ShortcutsTabView
struct ShortcutsTabView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    KeyboardShortcuts.Recorder(
                        "Open Command Search:",
                        name: .toggleCommandPalette
                    )
                    
                    KeyboardShortcuts.Recorder(
                        "Play/Pause Music:",
                        name: .togglePlayPause
                    )
                    
                    KeyboardShortcuts.Recorder(
                        "Next Music:",
                        name: .nextTrack
                    )
                    
                    KeyboardShortcuts.Recorder(
                        "Previous Music:",
                        name: .previousTrack
                    )
                }
                .padding(.vertical, 8)
            } header: {
                Text("DropBeat Shortcuts")
                    .font(.headline)
                    .padding(.leading, -8)
            }
        }
        .transparentGroupedForm()
    }
}

// MARK: - About Tab
struct AboutTabView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Top Section
            HStack(alignment: .center, spacing: 16) {
                // App Icon
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .frame(width: 72, height: 72)
                    .cornerRadius(16)
                
                // App Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("DropBeats")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Version 1.0.0")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Buttons
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Check for Updates") { }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    Button("Request Feature") { }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(width: 150)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxHeight: 100)  // Match app icon height
            
            Divider()
            
            // Description
            VStack(alignment: .leading, spacing: 16) {
                Text("Your personal assistant for YouTube Music")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 8) {
                    FeaturePoint(text: "Command Palette Search - Quick access to songs & artists")
                    FeaturePoint(text: "Global Shortcuts - Control music playback just by using shortcuts")
                    FeaturePoint(text: "Album Art Theme - Get a visually pleasing album art theme to the menu bar player")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            
            Divider()
            
            // Footer
            HStack {
                Text("Created with ❤️ by Sudhanva and Claude")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Social Links with custom icons
                HStack(spacing: 12) {
                    SocialButton(title: "Website", icon: "website", url: "https://sudhanva.webflow.io/")
                    SocialButton(title: "LinkedIn", icon: "linkedin", url: "https://www.linkedin.com/in/s-m-sudhanva-acharya/")
                    SocialButton(title: "Twitter", icon: "x", url: "https://twitter.com/SudhanvaAchary")
                    SocialButton(title: "Instagram", icon: "instagram", url: "https://www.instagram.com/sudhanva.design/")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}

struct FeaturePoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .foregroundColor(.secondary)
        }
    }
}

struct SocialButton: View {
    let title: String
    let icon: String
    let url: String
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: url)!)
        } label: {
            Image(icon)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .foregroundColor(.secondary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color(.controlBackgroundColor) : Color.clear)
                        .shadow(color: isHovering ? .black.opacity(0.1) : .clear, radius: 1, x: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(title)
    }
}

// MARK: - Helper Components
struct LicenseInfoRow: View {
    let title: String
    let value: String
    var valueColor: Color = .secondary
    var showCopy: Bool = false
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
            
            if showCopy {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct MaxFeatureRow: View {
    @Binding var isOn: Bool
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32, height: 32)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// Add this extension for custom form style
extension View {
    func transparentGroupedForm() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.clear)
    }
}

// Add this extension for bitmap capture
extension NSView {
    func bitmapImage() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage()
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

#Preview {
    SettingsView()
}
