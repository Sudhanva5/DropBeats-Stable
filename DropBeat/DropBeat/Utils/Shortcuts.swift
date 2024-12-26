import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleCommandPalette = Self("toggleCommandPalette", default: .init(.space, modifiers: [.command, .option]))
    static let togglePlayPause = Self("togglePlayPause", default: .init(.space, modifiers: [.control, .shift]))
    static let nextTrack = Self("nextTrack", default: .init(.rightArrow, modifiers: [.command]))
    static let previousTrack = Self("previousTrack", default: .init(.leftArrow, modifiers: [.command]))
    
    static func resetDefaults() {
        KeyboardShortcuts.reset(togglePlayPause)
    }
} 
