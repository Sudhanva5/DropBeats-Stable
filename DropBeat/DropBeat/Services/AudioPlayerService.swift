import Foundation
import AVFoundation
import Combine

/// Service that wraps AVPlayer for audio playback
class AudioPlayerService: ObservableObject {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var playerObserver: AnyCancellable?
    private var itemObserver: AnyCancellable?

    // Callbacks
    var onTimeUpdate: ((TimeInterval, TimeInterval) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?
    var onBufferingStateChanged: ((Bool) -> Void)?
    var onPlaybackFailed: ((Error) -> Void)?

    init() {
        // Observers are now set up per player item in setupPlayerItemObservers()
    }

    deinit {
        cleanup()
    }

    // MARK: - Public Methods

    /// Load and prepare a stream URL for playback
    func loadStream(url: URL) async throws {
        print("🎵 [AudioPlayerService] Loading stream: \(url.absoluteString.prefix(80))...")

        await MainActor.run {
            // Clean up existing player
            cleanup()

            // Create new player item
            let newPlayerItem = AVPlayerItem(url: url)
            playerItem = newPlayerItem

            // Create or reuse player
            if player == nil {
                player = AVPlayer(playerItem: newPlayerItem)
            } else {
                player?.replaceCurrentItem(with: newPlayerItem)
            }

            // Setup observers for new item
            setupPlayerItemObservers(newPlayerItem)
            setupTimeObserver()

            print("✅ [AudioPlayerService] Stream loaded successfully")
        }
    }

    /// Start playback
    func play() {
        guard let player = player else {
            print("⚠️ [AudioPlayerService] Cannot play: No player instance")
            return
        }

        player.play()
        onPlaybackStateChanged?(true)
        print("▶️ [AudioPlayerService] Playback started")
    }

    /// Pause playback
    func pause() {
        guard let player = player else {
            print("⚠️ [AudioPlayerService] Cannot pause: No player instance")
            return
        }

        player.pause()
        onPlaybackStateChanged?(false)
        print("⏸️ [AudioPlayerService] Playback paused")
    }

    /// Seek to a specific time
    func seek(to time: CMTime) {
        guard let player = player, let playerItem = playerItem else {
            print("⚠️ [AudioPlayerService] Cannot seek: No player instance")
            return
        }

        // Check if seeking is supported and the time is valid
        let duration = playerItem.duration
        guard duration.isNumeric && !duration.isIndefinite else {
            print("⚠️ [AudioPlayerService] Cannot seek: Duration not available")
            return
        }

        // Clamp seek time to valid range
        let seekTime = min(max(time, .zero), duration)

        print("⏩ [AudioPlayerService] Seeking to \(seekTime.seconds)s / \(duration.seconds)s...")

        // Use completion handler to detect seek issues
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            if finished {
                print("✅ [AudioPlayerService] Seek completed to \(seekTime.seconds)s")
            } else {
                print("⚠️ [AudioPlayerService] Seek was interrupted or failed")
            }

            // Notify buffering state in case seek requires rebuffering
            self?.onBufferingStateChanged?(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.onBufferingStateChanged?(false)
            }
        }
    }

    /// Get current playback time
    var currentTime: TimeInterval {
        player?.currentTime().seconds ?? 0
    }

    /// Get total duration
    var duration: TimeInterval {
        playerItem?.duration.seconds ?? 0
    }

    /// Check if player is currently playing
    var isPlaying: Bool {
        player?.rate ?? 0 > 0
    }

    // MARK: - Private Methods

    private func setupTimeObserver() {
        guard let player = player else { return }

        // Remove existing observer
        if let existingObserver = timeObserver {
            player.removeTimeObserver(existingObserver)
        }

        // Add periodic time observer (updates every 100ms for smooth scrubber)
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            let currentTime = time.seconds
            let duration = self.playerItem?.duration.seconds ?? 0

            // Only call callback if we have valid values
            if !currentTime.isNaN && !duration.isNaN && duration > 0 {
                // Clamp currentTime to duration to prevent UI showing time beyond track length
                let clampedTime = min(currentTime, duration)
                self.onTimeUpdate?(clampedTime, duration)
            }
        }
    }

    private func setupPlayerItemObservers(_ item: AVPlayerItem) {
        // Remove existing notification observers before adding new ones
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: nil)

        // Observe THIS specific player item's playback end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item  // Observe only this specific item
        )

        // Observe THIS specific player item's playback failures
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlay),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item  // Observe only this specific item
        )

        // Observe THIS specific player item's playback stalls
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: item  // Observe only this specific item
        )

        // Observe status changes
        itemObserver = item.publisher(for: \.status)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    print("✅ [AudioPlayerService] Player item ready to play")
                case .failed:
                    let error = item.error ?? PlaybackError.playerError("Unknown error")
                    print("❌ [AudioPlayerService] Player item failed: \(error.localizedDescription)")
                    self?.onPlaybackFailed?(error)
                case .unknown:
                    print("⚠️ [AudioPlayerService] Player item status unknown")
                @unknown default:
                    break
                }
            }

        // Observe buffering
        playerObserver = item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { [weak self] isLikelyToKeepUp in
                let isBuffering = !isLikelyToKeepUp
                self?.onBufferingStateChanged?(isBuffering)
                if isBuffering {
                    print("⏳ [AudioPlayerService] Buffering...")
                } else {
                    print("✅ [AudioPlayerService] Buffer ready")
                }
            }
    }

    @objc private func playerItemDidPlayToEnd(_ notification: Notification) {
        print("🔚 [AudioPlayerService] Playback ended notification received")
        print("🔚 [AudioPlayerService] Notification object: \(String(describing: notification.object))")
        print("🔚 [AudioPlayerService] Current playerItem: \(String(describing: playerItem))")
        print("🔚 [AudioPlayerService] Callback exists: \(onPlaybackEnded != nil)")

        if onPlaybackEnded != nil {
            print("🔚 [AudioPlayerService] Calling onPlaybackEnded callback")
            onPlaybackEnded?()
            print("🔚 [AudioPlayerService] onPlaybackEnded callback completed")
        } else {
            print("⚠️ [AudioPlayerService] No onPlaybackEnded callback set!")
        }
    }

    @objc private func playerItemFailedToPlay(_ notification: Notification) {
        if let item = notification.object as? AVPlayerItem,
           let error = item.error {
            print("❌ [AudioPlayerService] Playback failed: \(error.localizedDescription)")
            onPlaybackFailed?(error)
        }
    }

    @objc private func playerItemStalled(_ notification: Notification) {
        print("⚠️ [AudioPlayerService] Playback stalled")
        onBufferingStateChanged?(true)
    }

    private func cleanup() {
        // Remove time observer
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        // Cancel observers
        playerObserver?.cancel()
        itemObserver?.cancel()

        // Pause and clear player item
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerItem = nil
    }
}
