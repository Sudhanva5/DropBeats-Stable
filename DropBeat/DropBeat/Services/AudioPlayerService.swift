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
    private var stallTimeoutTask: Task<Void, Never>?
    private var shouldAutoPlayWhenReady = false  // BUGFIX: Track if we should auto-play when ready

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
        print("🗑️ [AudioPlayerService] Deinitializing...")
        // DEFENSIVE: Ensure cleanup happens even during deallocation
        cleanup()
        print("🗑️ [AudioPlayerService] Deinitialized")
    }

    // MARK: - Public Methods

    /// Load and prepare a stream URL for playback
    func loadStream(url: URL) async throws {
        print("🎵 [AudioPlayerService] Loading stream: \(url.absoluteString.prefix(80))...")

        await MainActor.run {
            // DEFENSIVE: Clean up existing player
            cleanup()

            // DEFENSIVE: Create AVPlayerItem with validation (known crash point on macOS 26)
            let newPlayerItem = AVPlayerItem(url: url)

            // DEFENSIVE: Verify item was created successfully
            guard newPlayerItem.asset.isPlayable else {
                print("❌ [AudioPlayerService] Asset is not playable")
                self.onPlaybackFailed?(PlaybackError.playerError("Asset is not playable"))
                return
            }

            playerItem = newPlayerItem
            print("✅ [AudioPlayerService] AVPlayerItem created successfully")

            // DEFENSIVE: Create or reuse player with additional validation
            if player == nil {
                player = AVPlayer(playerItem: newPlayerItem)
                guard player != nil else {
                    print("❌ [AudioPlayerService] Failed to create AVPlayer")
                    self.onPlaybackFailed?(PlaybackError.playerError("Failed to create AVPlayer"))
                    return
                }
                print("✅ [AudioPlayerService] AVPlayer created successfully")
            } else {
                // DEFENSIVE: Verify player is in valid state before replacing item
                guard player?.status != .failed else {
                    print("⚠️ [AudioPlayerService] Player in failed state, recreating...")
                    player = AVPlayer(playerItem: newPlayerItem)
                    return
                }
                player?.replaceCurrentItem(with: newPlayerItem)
            }

            // DEFENSIVE: Setup observers with error handling
            setupPlayerItemObservers(newPlayerItem)
            setupTimeObserver()

            print("✅ [AudioPlayerService] Stream loaded successfully")
        }
    }

    /// Start playback
    func play() {
        // DEFENSIVE: Validate player and item exist
        guard let player = player else {
            print("⚠️ [AudioPlayerService] Cannot play: No player instance")
            return
        }

        guard let playerItem = playerItem else {
            print("⚠️ [AudioPlayerService] Cannot play: No player item")
            return
        }

        // BUGFIX: If player item isn't ready yet, mark for auto-play when it becomes ready
        guard playerItem.status == .readyToPlay else {
            print("⏳ [AudioPlayerService] Player item not ready (status: \(playerItem.status.rawValue)) - will auto-play when ready")
            shouldAutoPlayWhenReady = true
            return
        }

        // DEFENSIVE: Check for errors before playing
        if let error = playerItem.error {
            print("⚠️ [AudioPlayerService] Cannot play: Player item has error: \(error)")
            onPlaybackFailed?(error)
            return
        }

        shouldAutoPlayWhenReady = false
        player.play()
        onPlaybackStateChanged?(true)
        print("▶️ [AudioPlayerService] Playback started")
    }

    /// Pause playback
    func pause() {
        // BUGFIX: Cancel auto-play if user pauses before track is ready
        shouldAutoPlayWhenReady = false

        // DEFENSIVE: Validate player exists
        guard let player = player else {
            print("⚠️ [AudioPlayerService] Cannot pause: No player instance")
            return
        }

        // DEFENSIVE: Only pause if actually playing
        guard player.rate > 0 else {
            print("⚠️ [AudioPlayerService] Cannot pause: Already paused")
            return
        }

        player.pause()
        onPlaybackStateChanged?(false)
        print("⏸️ [AudioPlayerService] Playback paused")
    }

    /// Seek to a specific time
    func seek(to time: CMTime) {
        // DEFENSIVE: Validate player and item exist
        guard let player = player, let playerItem = playerItem else {
            print("⚠️ [AudioPlayerService] Cannot seek: No player instance")
            return
        }

        // DEFENSIVE: Verify player item is ready for seeking
        guard playerItem.status == .readyToPlay else {
            print("⚠️ [AudioPlayerService] Cannot seek: Player item not ready (status: \(playerItem.status.rawValue))")
            return
        }

        // DEFENSIVE: Check if seeking is supported and the time is valid
        let duration = playerItem.duration
        guard duration.isNumeric && !duration.isIndefinite else {
            print("⚠️ [AudioPlayerService] Cannot seek: Duration not available")
            return
        }

        // DEFENSIVE: Validate seek time is numeric
        guard time.isNumeric && !time.isIndefinite else {
            print("⚠️ [AudioPlayerService] Cannot seek: Invalid seek time")
            return
        }

        // DEFENSIVE: Clamp seek time to valid range
        let seekTime = min(max(time, .zero), duration)

        print("⏩ [AudioPlayerService] Seeking to \(seekTime.seconds)s / \(duration.seconds)s...")

        // DEFENSIVE: Use completion handler to detect seek issues
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
        // DEFENSIVE: Verify player exists before setting up observer
        guard let player = player else {
            print("⚠️ [AudioPlayerService] Cannot setup time observer: No player instance")
            return
        }

        // DEFENSIVE: Remove existing observer to prevent multiple observers
        if let existingObserver = timeObserver {
            player.removeTimeObserver(existingObserver)
            timeObserver = nil
            print("🔄 [AudioPlayerService] Removed existing time observer")
        }

        // Add periodic time observer (updates every 100ms for smooth scrubber)
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }

            // DEFENSIVE: Validate time values before using them
            guard time.isNumeric && !time.isIndefinite else {
                return
            }

            let currentTime = time.seconds
            let duration = self.playerItem?.duration.seconds ?? 0

            // DEFENSIVE: Only call callback if we have valid values
            if !currentTime.isNaN && !duration.isNaN && duration > 0 {
                // Clamp currentTime to duration to prevent UI showing time beyond track length
                let clampedTime = min(currentTime, duration)
                self.onTimeUpdate?(clampedTime, duration)
            }
        }
        print("✅ [AudioPlayerService] Time observer setup complete")
    }

    private func setupPlayerItemObservers(_ item: AVPlayerItem) {
        // DEFENSIVE: Remove existing notification observers before adding new ones
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: nil)
        print("🔄 [AudioPlayerService] Removed existing notification observers")

        // DEFENSIVE: Cancel existing Combine observers before creating new ones
        itemObserver?.cancel()
        playerObserver?.cancel()

        // DEFENSIVE: Observe THIS specific player item's playback end
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item  // Observe only this specific item
        )

        // DEFENSIVE: Observe THIS specific player item's playback failures
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlay),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item  // Observe only this specific item
        )

        // DEFENSIVE: Observe THIS specific player item's playback stalls
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: item  // Observe only this specific item
        )

        // DEFENSIVE: Observe status changes with error handling
        itemObserver = item.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self = self else { return }

                switch status {
                case .readyToPlay:
                    print("✅ [AudioPlayerService] Player item ready to play")

                    // BUGFIX: Auto-play if play() was called before item was ready
                    if self.shouldAutoPlayWhenReady {
                        print("▶️ [AudioPlayerService] Auto-playing now that item is ready")
                        self.shouldAutoPlayWhenReady = false
                        self.player?.play()
                        self.onPlaybackStateChanged?(true)
                    }
                case .failed:
                    let error = item.error ?? PlaybackError.playerError("Unknown error")
                    print("❌ [AudioPlayerService] Player item failed: \(error.localizedDescription)")
                    self.onPlaybackFailed?(error)

                    // DEFENSIVE: Attempt recovery by recreating player
                    DispatchQueue.main.async {
                        print("🔄 [AudioPlayerService] Attempting player recovery after failure")
                        self.cleanup()
                    }
                case .unknown:
                    print("⚠️ [AudioPlayerService] Player item status unknown")
                @unknown default:
                    print("⚠️ [AudioPlayerService] Player item unknown status case")
                    break
                }
            }

        // DEFENSIVE: Observe buffering with null checks
        playerObserver = item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { [weak self] isLikelyToKeepUp in
                guard let self = self else { return }
                let isBuffering = !isLikelyToKeepUp
                self.onBufferingStateChanged?(isBuffering)
                if isBuffering {
                    print("⏳ [AudioPlayerService] Buffering...")
                } else {
                    print("✅ [AudioPlayerService] Buffer ready")
                    // BUGFIX: Cancel stall timeout when playback resumes
                    self.stallTimeoutTask?.cancel()
                    self.stallTimeoutTask = nil
                }
            }

        print("✅ [AudioPlayerService] Player item observers setup complete")
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

        // BUGFIX: Start timeout task - if playback doesn't resume in 15 seconds, treat as failure
        // This prevents tracks from hanging indefinitely when network times out
        stallTimeoutTask?.cancel()
        stallTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                guard !Task.isCancelled else { return }

                print("❌ [AudioPlayerService] Playback stalled for 15s - triggering failure")
                await MainActor.run {
                    self?.onPlaybackFailed?(PlaybackError.playerError("Playback stalled - network timeout"))
                }
            } catch {
                // Task cancelled - playback resumed
                print("✅ [AudioPlayerService] Stall timeout cancelled - playback resumed")
            }
        }
    }

    private func cleanup() {
        print("🧹 [AudioPlayerService] Starting cleanup...")

        // BUGFIX: Reset auto-play flag
        shouldAutoPlayWhenReady = false

        // DEFENSIVE: Cancel stall timeout task if running
        stallTimeoutTask?.cancel()
        stallTimeoutTask = nil
        print("🧹 [AudioPlayerService] Cancelled stall timeout task")

        // DEFENSIVE: Remove time observer safely
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
            timeObserver = nil
            print("🧹 [AudioPlayerService] Removed time observer")
        }

        // DEFENSIVE: Cancel Combine observers
        playerObserver?.cancel()
        playerObserver = nil
        itemObserver?.cancel()
        itemObserver = nil
        print("🧹 [AudioPlayerService] Cancelled Combine observers")

        // DEFENSIVE: Remove NotificationCenter observers
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: nil)
        print("🧹 [AudioPlayerService] Removed notification observers")

        // DEFENSIVE: Pause player if it exists and is playing
        if let player = player, player.rate > 0 {
            player.pause()
            print("🧹 [AudioPlayerService] Paused player")
        }

        // DEFENSIVE: Clear player item safely
        player?.replaceCurrentItem(with: nil)
        playerItem = nil
        print("🧹 [AudioPlayerService] Cleared player item")

        print("✅ [AudioPlayerService] Cleanup complete")
    }
}
