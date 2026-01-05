import Foundation
import SwiftUI
import AVFoundation

/// Main manager that orchestrates playback, queue management, and state publishing
@MainActor
class MusicPlayerManager: ObservableObject {
    static let shared = MusicPlayerManager()

    // Published state for UI
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var recentTracks: [Track] = []
    @Published private(set) var playbackQueue: [PlaybackQueueItem] = []
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var isBuffering: Bool = false

    // Services
    private let audioPlayer = AudioPlayerService()
    private let ytdlpService = YTDLPService.shared
    private let recommendationService = RecommendationService.shared
    private let songInfoService = SongInfoService.shared

    // State
    private var currentQueueIndex: Int = 0
    private let maxRecentTracks = 7
    private var currentLoadingTrackId: String? = nil
    private var trackHistory: [Track] = []  // Stack for previous track functionality
    private let maxHistorySize = 50
    private var hasTriggeredAutoPlay = false  // Track if we've triggered auto-play for current track
    private var consecutiveFailures = 0  // Track consecutive playback failures to prevent infinite loops
    private let maxConsecutiveFailures = 3  // Stop auto-skipping after this many failures

    private init() {
        setupAudioPlayerCallbacks()
        print("🎵 [MusicPlayerManager] Initialized")
    }

    // MARK: - Public Methods

    /// Play a track by video ID
    func play(trackId: String, trackMetadata: Track? = nil, type: SearchResultType = .song) async {
        print("🎵 [MusicPlayerManager] Playing track: \(trackId)")

        // Reset auto-play flag for new track
        hasTriggeredAutoPlay = false

        // BUGFIX: Reset consecutive failures when user manually plays a track
        consecutiveFailures = 0

        // Pause current playback while loading new track
        audioPlayer.pause()
        isPlaying = false

        // BUGFIX: Reset scrubber to 0:00 immediately to prevent showing old track's time
        currentTime = 0
        duration = 0

        // Set this as the currently loading track
        currentLoadingTrackId = trackId
        playbackState = .loading

        // NOTE: Keep old currentTrack visible during loading - skeleton loader will show over it
        // Only update currentTrack after everything is ready to avoid flash of new track info

        do {
            // OPTIMIZATION: Fetch stream URL and song info in parallel for faster loading
            async let streamURLFetch = ytdlpService.getStreamURL(videoId: trackId)
            async let songInfoFetch = songInfoService.getSongInfo(videoId: trackId)

            let streamURL: URL
            var accurateDuration: TimeInterval? = nil
            var accurateThumbnail: String? = nil

            // Wait for stream URL (required for playback)
            streamURL = try await streamURLFetch

            // Check if we're still supposed to be playing this track
            guard currentLoadingTrackId == trackId else {
                print("⏭️ [MusicPlayerManager] Skipping \(trackId) - new track requested")
                return
            }

            // Load stream while song info may still be fetching
            try await audioPlayer.loadStream(url: streamURL)

            // Final check before playing
            guard currentLoadingTrackId == trackId else {
                print("⏭️ [MusicPlayerManager] Skipping \(trackId) - new track requested")
                return
            }

            // Try to get song info (should be ready or almost ready by now)
            do {
                let songInfo = try await songInfoFetch
                accurateDuration = songInfo.duration
                accurateThumbnail = songInfo.thumbnail
                print("✅ [MusicPlayerManager] Got accurate duration: \(Int(songInfo.duration / 60)):\(String(format: "%02d", Int(songInfo.duration.truncatingRemainder(dividingBy: 60))))")
            } catch {
                print("⚠️ [MusicPlayerManager] Failed to fetch accurate duration: \(error.localizedDescription)")
            }

            // Update currentTrack with accurate info now that stream is loaded
            if let metadata = trackMetadata {
                // Use accurate duration if available, otherwise keep original
                let finalDuration = accurateDuration ?? metadata.duration
                let finalAlbumArt = accurateThumbnail ?? metadata.albumArt

                // Update with accurate info (keeps the track visible, just updates the details)
                currentTrack = Track(
                    id: metadata.id,
                    title: metadata.title,
                    artist: metadata.artist,
                    albumArt: finalAlbumArt,
                    duration: finalDuration,
                    isLiked: metadata.isLiked,
                    isPlaying: false,  // Will be set to true when buffer threshold met
                    currentTime: 0
                )

                // Set duration from accurate Track metadata, not from AVPlayer
                duration = finalDuration

                print("✅ [MusicPlayerManager] Updated track with accurate info: \(metadata.title)")
                print("📊 [MusicPlayerManager] Accurate duration: \(Int(finalDuration / 60)):\(String(format: "%02d", Int(finalDuration.truncatingRemainder(dividingBy: 60))))")
            }

            // Get actual duration from AVPlayer and compare with accurate duration
            let actualDuration = audioPlayer.duration
            if actualDuration > 0 {
                print("📊 [MusicPlayerManager] AVPlayer duration: \(Int(actualDuration / 60)):\(String(format: "%02d", Int(actualDuration.truncatingRemainder(dividingBy: 60))))")

                // Compare with accurate duration from YouTube Music API
                if let apiDuration = accurateDuration, abs(actualDuration - apiDuration) > 10 {
                    print("⚠️ [MusicPlayerManager] DURATION MISMATCH!")
                    print("   📊 YouTube Music API: \(Int(apiDuration / 60)):\(String(format: "%02d", Int(apiDuration.truncatingRemainder(dividingBy: 60)))) (\(Int(apiDuration))s)")
                    print("   📊 Actual stream (AVPlayer): \(Int(actualDuration / 60)):\(String(format: "%02d", Int(actualDuration.truncatingRemainder(dividingBy: 60)))) (\(Int(actualDuration))s)")
                    print("   📊 Difference: \(Int(abs(actualDuration - apiDuration)))s")
                    print("   🎵 VideoId: \(trackId)")
                    print("   ⚠️  This likely means a different version (extended/live) is being played")
                }
            }

            audioPlayer.play()

            playbackState = .playing
            isPlaying = true

            // BUGFIX: Reset consecutive failure counter on successful playback
            consecutiveFailures = 0

            // Add to recent tracks if we have track metadata
            if let track = currentTrack, track.id == trackId {
                addToRecentTracks(track: track)
            }

            // Initialize queue for this track if empty
            if playbackQueue.isEmpty {
                await refillQueue(basedOn: trackId)
            }

            // OPTIMIZATION: Proactively pre-fetch upcoming tracks as soon as playback starts
            Task {
                await prefetchUpcomingStreams()
            }

        } catch let error as PlaybackError {
            // Only handle error if this is still the track we care about
            guard currentLoadingTrackId == trackId else {
                print("⏭️ [MusicPlayerManager] Ignoring error for \(trackId) - new track requested")
                return
            }
            await handlePlaybackError(error, trackId: trackId)
        } catch {
            // Only handle error if this is still the track we care about
            guard currentLoadingTrackId == trackId else {
                print("⏭️ [MusicPlayerManager] Ignoring error for \(trackId) - new track requested")
                return
            }
            await handlePlaybackError(.playerError(error.localizedDescription), trackId: trackId)
        }
    }

    /// Play a complete Track object (from search results)
    func play(track: Track, addToHistory: Bool = true) async {
        guard let trackId = track.id else {
            print("⚠️ [MusicPlayerManager] Cannot play track without ID")
            return
        }

        // Add current track to history before playing new one
        if addToHistory, let previousTrack = currentTrack, previousTrack.id != track.id {
            trackHistory.append(previousTrack)
            // Keep history size manageable
            if trackHistory.count > maxHistorySize {
                trackHistory.removeFirst()
            }
            print("📚 [MusicPlayerManager] Added to history: \(previousTrack.title) (history size: \(trackHistory.count))")
        }

        print("🎨 [MusicPlayerManager] Preparing track - Title: \(track.title), Artist: \(track.artist), AlbumArt: \(track.albumArt ?? "nil")")

        // Set loading state but don't update currentTrack yet
        // This prevents UI from showing metadata before stream is ready
        playbackState = .loading

        // Fetch and load the stream
        await play(trackId: trackId, trackMetadata: track)
    }

    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// Pause playback
    func pause() {
        audioPlayer.pause()
        isPlaying = false
        playbackState = .paused
        updateCurrentTrackPlayingState(false)
        print("⏸️ [MusicPlayerManager] Paused")
    }

    /// Resume playback
    func resume() {
        audioPlayer.play()
        isPlaying = true
        playbackState = .playing
        updateCurrentTrackPlayingState(true)
        print("▶️ [MusicPlayerManager] Resumed")
    }

    /// Skip to next track in queue
    func next() {
        // Prevent race conditions: Don't allow next if already loading a track
        guard playbackState != .loading else {
            print("⏭️ [MusicPlayerManager] Next ignored - already loading a track")
            return
        }

        Task {
            await playNext()
        }
    }

    /// Go to previous track (restart current track for now)
    func previous() {
        // Prevent race conditions: Don't allow previous if already loading a track
        guard playbackState != .loading else {
            print("⏮️ [MusicPlayerManager] Previous ignored - already loading a track")
            return
        }

        Task {
            await playPrevious()
        }
    }

    /// Seek to a specific time
    func seek(to position: TimeInterval) {
        let time = CMTime(seconds: position, preferredTimescale: 600)
        audioPlayer.seek(to: time)
        print("⏩ [MusicPlayerManager] Seeked to \(position)s")
    }

    // MARK: - Private Methods

    private func setupAudioPlayerCallbacks() {
        print("🎵 [MusicPlayerManager] Setting up audio player callbacks")

        // Time updates for scrubber
        audioPlayer.onTimeUpdate = { [weak self] current, total in
            guard let self = self else { return }
            Task { @MainActor in
                self.currentTime = current
                // Don't update duration from AVPlayer - use accurate duration from Track metadata instead
                // AVPlayer's duration can be incorrect (e.g., wrong video version, extended/live versions)

                // Check if we've reached the end using ACCURATE duration, not AVPlayer's duration
                // Use 1.0s threshold to prevent premature triggering if user seeks near end
                if !self.hasTriggeredAutoPlay && self.duration > 0 && current >= (self.duration - 1.0) {
                    print("🔚 [MusicPlayerManager] Detected end of track via accurate duration")
                    print("🔚 [MusicPlayerManager] currentTime: \(current), accurate duration: \(self.duration)")
                    print("🔚 [MusicPlayerManager] AVPlayer duration was: \(total)")
                    self.hasTriggeredAutoPlay = true

                    // Trigger auto-play to next track
                    print("🔚 [MusicPlayerManager] Triggering auto-play to next track...")
                    await self.playNext()
                }
            }
        }

        // Playback ended - play next
        audioPlayer.onPlaybackEnded = { [weak self] in
            print("🔚 [MusicPlayerManager] onPlaybackEnded callback triggered!")
            guard let self = self else {
                print("⚠️ [MusicPlayerManager] self is nil in onPlaybackEnded callback")
                return
            }
            Task { @MainActor in
                print("🔚 [MusicPlayerManager] Task started on MainActor")
                print("🔚 [MusicPlayerManager] About to call playNext()")
                await self.playNext()
                print("🔚 [MusicPlayerManager] playNext() returned")
            }
        }

        print("✅ [MusicPlayerManager] Audio player callbacks set up complete")

        // Playback state changes
        audioPlayer.onPlaybackStateChanged = { [weak self] playing in
            guard let self = self else { return }
            Task { @MainActor in
                self.isPlaying = playing
                self.playbackState = playing ? .playing : .paused
                self.updateCurrentTrackPlayingState(playing)
            }
        }

        // Buffering state
        audioPlayer.onBufferingStateChanged = { [weak self] buffering in
            guard let self = self else { return }
            Task { @MainActor in
                self.isBuffering = buffering
                if buffering {
                    self.playbackState = .buffering
                }
            }
        }

        // Loading state (waiting for buffer threshold before playback)
        audioPlayer.onLoadingStateChanged = { [weak self] loading in
            guard let self = self else { return }
            Task { @MainActor in
                if loading {
                    // Show loading state while waiting for buffer threshold
                    self.playbackState = .loading
                    print("⏳ [MusicPlayerManager] Waiting for buffer threshold...")
                } else {
                    // Buffer threshold met, playback will start
                    print("✅ [MusicPlayerManager] Buffer threshold met - ready to play")
                }
            }
        }

        // Playback failures
        audioPlayer.onPlaybackFailed = { [weak self] error in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handlePlaybackError(.playerError(error.localizedDescription), trackId: self.currentTrack?.id)
            }
        }
    }

    private func playNext() async {
        print("⏭️ [MusicPlayerManager] ========== PLAY NEXT CALLED ==========")
        print("⏭️ [MusicPlayerManager] Current queue size: \(playbackQueue.count)")
        print("⏭️ [MusicPlayerManager] Current track: \(currentTrack?.title ?? "nil")")

        // Check if we need to refill the queue
        if recommendationService.shouldFetchMore(currentQueueSize: playbackQueue.count, threshold: 5) {
            print("⏭️ [MusicPlayerManager] Queue needs refilling")
            if let currentId = currentTrack?.id {
                await refillQueue(basedOn: currentId)
            }
        }

        // Get next track from queue
        guard !playbackQueue.isEmpty else {
            print("⚠️ [MusicPlayerManager] Queue is empty - cannot play next")
            playbackState = .idle
            return
        }

        let nextItem = playbackQueue.removeFirst()
        print("⏭️ [MusicPlayerManager] Next track: \(nextItem.track.title)")
        print("⏭️ [MusicPlayerManager] Calling play(track:)")
        await play(track: nextItem.track)
        print("⏭️ [MusicPlayerManager] play(track:) completed")

        // Pre-fetch stream URLs for next 2-3 tracks
        print("⏭️ [MusicPlayerManager] Pre-fetching upcoming streams")
        await prefetchUpcomingStreams()
        print("⏭️ [MusicPlayerManager] ========== PLAY NEXT COMPLETED ==========")
    }

    private func playPrevious() async {
        // If more than 3 seconds into the track, restart it
        if currentTime > 3.0 {
            seek(to: 0)
            print("⏮️ [MusicPlayerManager] Restarting current track")
        } else if !trackHistory.isEmpty {
            // Go back to previous track from history
            let previousTrack = trackHistory.removeLast()
            print("⏮️ [MusicPlayerManager] Going back to: \(previousTrack.title)")
            // Don't add current track to history when going back (avoid infinite loop)
            await play(track: previousTrack, addToHistory: false)
        } else {
            // No history, just restart current track
            seek(to: 0)
            print("⏮️ [MusicPlayerManager] No history, restarting current track")
        }
    }

    private func refillQueue(basedOn videoId: String) async {
        print("🔄 [MusicPlayerManager] Refilling queue based on \(videoId)...")

        do {
            let recommendations = try await recommendationService.getWatchPlaylist(videoId: videoId)

            // BUGFIX: Filter out the current track and any tracks already in the queue
            // YouTube Music's watch playlist often returns the current track as the first recommendation
            let existingTrackIds = Set(playbackQueue.compactMap { $0.track.id })
            let filteredRecommendations = recommendations.filter { track in
                guard let trackId = track.id else { return false }
                // Exclude current track and tracks already in queue to avoid duplicates
                return trackId != videoId && !existingTrackIds.contains(trackId)
            }

            print("🔄 [MusicPlayerManager] Filtered \(recommendations.count) recommendations to \(filteredRecommendations.count) (removed current track and duplicates)")

            // Convert to queue items
            let newItems = filteredRecommendations.map { track in
                PlaybackQueueItem(id: track.id ?? UUID().uuidString, track: track)
            }

            playbackQueue.append(contentsOf: newItems)
            print("✅ [MusicPlayerManager] Added \(newItems.count) tracks to queue (total: \(playbackQueue.count))")

        } catch {
            print("❌ [MusicPlayerManager] Failed to refill queue: \(error.localizedDescription)")
        }
    }

    private func prefetchUpcomingStreams() async {
        // RATE LIMITING: Pre-fetch next 3 tracks with sequential delays to avoid YouTube throttling
        // First track is fetched immediately, remaining tracks with 1.5s delays between each
        let itemsToPrefetch = Array(playbackQueue.prefix(3))
        let videoIds = itemsToPrefetch.compactMap { $0.track.id }

        if !videoIds.isEmpty {
            print("🚀 [MusicPlayerManager] Pre-fetching \(videoIds.count) upcoming tracks for instant playback")
            // Pre-fetch both stream URLs and song info in parallel
            async let streamPrefetch = ytdlpService.prefetchStreamURLs(videoIds: videoIds)
            async let infoPrefetch = songInfoService.prefetchSongInfo(videoIds: videoIds)

            await streamPrefetch
            await infoPrefetch
        }
    }

    private func handlePlaybackError(_ error: PlaybackError, trackId: String?) async {
        print("❌ [MusicPlayerManager] Playback error: \(error.localizedDescription)")

        playbackState = .failed(error)

        // BUGFIX: Increment consecutive failure counter
        consecutiveFailures += 1
        print("⚠️ [MusicPlayerManager] Consecutive failures: \(consecutiveFailures)/\(maxConsecutiveFailures)")

        // BUGFIX: Stop auto-skipping after too many consecutive failures to prevent infinite loops
        if consecutiveFailures >= maxConsecutiveFailures {
            print("🛑 [MusicPlayerManager] Reached max consecutive failures (\(maxConsecutiveFailures)) - stopping auto-skip")
            NotificationCenter.default.post(
                name: NSNotification.Name("PlaybackError"),
                object: nil,
                userInfo: ["error": "Multiple tracks failed to play. Please check your network connection."]
            )
            return
        }

        // Show toast notification
        NotificationCenter.default.post(
            name: NSNotification.Name("PlaybackError"),
            object: nil,
            userInfo: ["error": error.localizedDescription]
        )

        // Auto-skip to next track for unavailable videos, network failures, and stalled playback
        switch error {
        case .videoUnavailable:
            print("⏭️ [MusicPlayerManager] Auto-skipping unavailable track...")
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await playNext()
        case .playerError(let message) where message.contains("stalled") || message.contains("timeout"):
            print("⏭️ [MusicPlayerManager] Auto-skipping stalled/timed-out track...")
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await playNext()
        default:
            // Don't auto-skip for other errors
            break
        }
    }

    private func addToRecentTracks(track: Track) {
        // Remove duplicate if it exists anywhere in the array
        if let existingIndex = recentTracks.firstIndex(where: { $0.id == track.id }) {
            recentTracks.remove(at: existingIndex)
        }

        // Insert at beginning
        recentTracks.insert(track, at: 0)

        // Keep only last N tracks
        if recentTracks.count > maxRecentTracks {
            recentTracks = Array(recentTracks.prefix(maxRecentTracks))
        }
    }

    private func updateCurrentTrackPlayingState(_ isPlaying: Bool) {
        guard var track = currentTrack else { return }

        currentTrack = Track(
            id: track.id,
            title: track.title,
            artist: track.artist,
            albumArt: track.albumArt,
            duration: track.duration,
            isLiked: track.isLiked,
            isPlaying: isPlaying,
            currentTime: currentTime
        )
    }
}
