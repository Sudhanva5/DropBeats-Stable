import SwiftUI

@Observable
@MainActor
final class CommandPaletteState {
    static let shared = CommandPaletteState()
    var searchText = ""
    var isVisible = false

    private init() {}
}

/// Lock-free visibility flag readable from the global event-tap thread.
///
/// The tap callback used to read `CommandPaletteState.isVisible` by hopping to
/// the main thread and blocking on a DispatchSemaphore — on every keystroke
/// typed anywhere on the machine. Blocking inside a tap callback is what makes
/// macOS disable the tap with kCGEventTapDisabledByTimeout, after which the
/// global hotkey is dead until the app restarts.
///
/// This is deliberately kept OUT of CommandPaletteState: that type is
/// `@Observable`, and the Observation macro rewrites stored properties into
/// computed ones, so a `didSet` on `isVisible` would not survive the macro.
/// Callers set `PaletteVisibility.isVisible` alongside `state.isVisible`.
enum PaletteVisibility {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _isVisible = false

    static var isVisible: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isVisible
        }
        set {
            lock.lock()
            _isVisible = newValue
            lock.unlock()
        }
    }
}
