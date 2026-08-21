import Foundation

@MainActor
final class CommandPaletteState {
    static let shared = CommandPaletteState()
    var searchText = ""

    var isVisible = false {
        didSet {
            // Mirror into a lock-free flag the global event tap can read.
            //
            // The tap callback runs on its own thread and used to hop to the
            // main thread with a DispatchSemaphore to read this value — on
            // EVERY keystroke typed anywhere on the machine. Blocking inside a
            // tap callback is what makes macOS disable the tap with
            // kCGEventTapDisabledByTimeout, after which the global hotkey is
            // dead until the app restarts. An atomic read costs nothing and
            // cannot block.
            PaletteVisibility.isVisible = isVisible
        }
    }

    private init() {}
}

/// Lock-free visibility flag readable from the event-tap thread.
///
/// Deliberately a plain global with atomic access rather than anything that
/// can wait: the only correct amount of blocking inside a CGEvent tap callback
/// is none.
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
