import Foundation

/// Represents the current state of the music player
enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case failed(Error)

    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.loading, .loading),
             (.playing, .playing),
             (.paused, .paused),
             (.buffering, .buffering):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Represents an item in the playback queue with cached stream information
struct PlaybackQueueItem: Identifiable, Equatable {
    let id: String
    let track: Track
    var streamURL: URL?
    var streamExpiresAt: Date?

    /// Check if the stream URL is still valid
    var isStreamValid: Bool {
        guard let expiresAt = streamExpiresAt else { return false }
        return Date() < expiresAt
    }

    /// Check if the stream URL needs refresh (within 5 minutes of expiry)
    var needsRefresh: Bool {
        guard let expiresAt = streamExpiresAt else { return true }
        let fiveMinutesBeforeExpiry = expiresAt.addingTimeInterval(-300)
        return Date() >= fiveMinutesBeforeExpiry
    }
}

/// Error types for playback operations
enum PlaybackError: Error, LocalizedError {
    case streamURLFetchFailed(String)
    case streamURLExpired
    case networkError
    case videoUnavailable(String)
    case playerError(String)
    case queueEmpty

    var errorDescription: String? {
        switch self {
        case .streamURLFetchFailed(let message):
            return "Failed to fetch stream URL: \(message)"
        case .streamURLExpired:
            return "Stream URL has expired"
        case .networkError:
            return "Network connection error"
        case .videoUnavailable(let videoId):
            return "Video \(videoId) is unavailable or region-locked"
        case .playerError(let message):
            return "Playback error: \(message)"
        case .queueEmpty:
            return "Playback queue is empty"
        }
    }
}
