import SwiftUI

@Observable
@MainActor
final class CommandPaletteState {
    static let shared = CommandPaletteState()
    var searchText = ""
    var isVisible = false
    
    private init() {}
} 