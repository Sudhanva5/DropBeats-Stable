import Foundation

/// Service for fetching auto-play recommendations from YouTube Music
class RecommendationService {
    static let shared = RecommendationService()

    private let backendURL = BackendConfig.baseURL
    private var recommendationCache: [String: CachedRecommendations] = [:]
    private let cacheQueue = DispatchQueue(label: "com.sudhanva.dropbeat.recommendations.cache")
    private let cacheExpiry: TimeInterval = 300 // 5 minutes

    private struct CachedRecommendations {
        let tracks: [Track]
        let fetchedAt: Date
    }

    private struct WatchPlaylistResponse: Codable {
        let tracks: [TrackResponse]
        let total: Int
    }

    private struct TrackResponse: Codable {
        let id: String
        let title: String
        let artist: String
        let albumArt: String?
        let duration: TimeInterval
        let isLiked: Bool
        let isPlaying: Bool
        let currentTime: TimeInterval
    }

    private init() {}

    /// Get auto-play recommendations for a video (YouTube Music Radio)
    func getWatchPlaylist(videoId: String, limit: Int = 25) async throws -> [Track] {
        // Check cache first
        if let cached = getCachedRecommendations(videoId),
           Date().timeIntervalSince(cached.fetchedAt) < cacheExpiry {
            print("🎵 [RecommendationService] Using cached recommendations for \(videoId)")
            return cached.tracks
        }

        // Fetch from backend
        print("🎵 [RecommendationService] Fetching recommendations for \(videoId)...")

        var components = URLComponents(string: "\(backendURL)/watch-playlist/\(videoId)")!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        guard let url = components.url else {
            throw PlaybackError.networkError
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaybackError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            throw PlaybackError.streamURLFetchFailed("Recommendations fetch failed: HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        let watchResponse = try decoder.decode(WatchPlaylistResponse.self, from: data)

        // Convert to Track objects
        let tracks = watchResponse.tracks.map { trackResponse in
            let track = Track(
                id: trackResponse.id,
                title: trackResponse.title,
                artist: trackResponse.artist,
                albumArt: trackResponse.albumArt,
                duration: trackResponse.duration,
                isLiked: trackResponse.isLiked,
                isPlaying: trackResponse.isPlaying,
                currentTime: trackResponse.currentTime
            )

            // Debug logging for album art
            if trackResponse.albumArt == nil {
                print("⚠️ [RecommendationService] Track '\(trackResponse.title)' has no albumArt in JSON response")
            }

            return track
        }

        // Cache the recommendations
        cacheRecommendations(videoId: videoId, tracks: tracks)

        print("✅ [RecommendationService] Fetched \(tracks.count) recommendations for \(videoId)")
        print("🎨 [RecommendationService] Sample track albumArt: \(tracks.first?.albumArt ?? "nil")")
        return tracks
    }

    /// Check if the queue should be refilled
    func shouldFetchMore(currentQueueSize: Int, threshold: Int = 5) -> Bool {
        return currentQueueSize < threshold
    }

    /// Clear expired recommendations from cache
    func clearExpiredCache() {
        cacheQueue.async {
            let now = Date()
            self.recommendationCache = self.recommendationCache.filter {
                now.timeIntervalSince($0.value.fetchedAt) < self.cacheExpiry
            }
            print("🎵 [RecommendationService] Cleared expired cache entries")
        }
    }

    // MARK: - Private Methods

    private func getCachedRecommendations(_ videoId: String) -> CachedRecommendations? {
        cacheQueue.sync {
            return recommendationCache[videoId]
        }
    }

    private func cacheRecommendations(videoId: String, tracks: [Track]) {
        cacheQueue.async {
            self.recommendationCache[videoId] = CachedRecommendations(
                tracks: tracks,
                fetchedAt: Date()
            )
        }
    }
}
