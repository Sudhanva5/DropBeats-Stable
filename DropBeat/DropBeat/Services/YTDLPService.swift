import Foundation

/// Service for fetching yt-dlp stream URLs from the backend
class YTDLPService {
    static let shared = YTDLPService()

    private let backendURL = "http://localhost:8000"
    private var streamCache: [String: CachedStream] = [:]
    private let cacheQueue = DispatchQueue(label: "com.sudhanva.dropbeat.ytdlp.cache")

    private struct CachedStream {
        let url: URL
        let expiresAt: Date
    }

    private struct StreamURLResponse: Codable {
        let videoId: String
        let streamUrl: String
        let expiresAt: String
    }

    private init() {}

    /// Get stream URL for a video ID, using cache if available
    func getStreamURL(videoId: String) async throws -> URL {
        // Check cache first
        if let cached = getCachedStream(videoId), cached.expiresAt > Date() {
            print("🎵 [YTDLPService] Using cached stream URL for \(videoId)")
            return cached.url
        }

        // Fetch from backend
        print("🎵 [YTDLPService] Fetching stream URL for \(videoId)...")
        let url = URL(string: "\(backendURL)/stream-url/\(videoId)")!

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaybackError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 500 || httpResponse.statusCode == 504 {
                throw PlaybackError.videoUnavailable(videoId)
            }
            throw PlaybackError.streamURLFetchFailed("HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        let streamResponse = try decoder.decode(StreamURLResponse.self, from: data)

        guard let streamURL = URL(string: streamResponse.streamUrl) else {
            throw PlaybackError.streamURLFetchFailed("Invalid stream URL")
        }

        // Parse expiry date (backend returns ISO 8601 with fractional seconds)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var expiresAt: Date?

        // Try ISO8601 with fractional seconds first
        expiresAt = isoFormatter.date(from: streamResponse.expiresAt)

        // Fallback to custom formatter if needed
        if expiresAt == nil {
            let customFormatter = DateFormatter()
            customFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            customFormatter.locale = Locale(identifier: "en_US_POSIX")
            customFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            expiresAt = customFormatter.date(from: streamResponse.expiresAt)
        }

        guard let validExpiresAt = expiresAt else {
            print("❌ [YTDLPService] Failed to parse date: \(streamResponse.expiresAt)")
            throw PlaybackError.streamURLFetchFailed("Invalid expiry date")
        }

        // Cache the stream
        cacheStream(videoId: videoId, url: streamURL, expiresAt: validExpiresAt)

        print("✅ [YTDLPService] Got stream URL for \(videoId), expires at \(validExpiresAt)")
        return streamURL
    }

    /// Pre-fetch stream URLs for multiple videos in parallel
    func prefetchStreamURLs(videoIds: [String]) async {
        print("🎵 [YTDLPService] Pre-fetching \(videoIds.count) stream URLs...")

        await withTaskGroup(of: Void.self) { group in
            for videoId in videoIds {
                // OPTIMIZATION: Only skip if cached URL is valid for at least 30 minutes (was 5 minutes)
                // This ensures we refresh URLs more aggressively before they expire during playback
                if let cached = getCachedStream(videoId), cached.expiresAt > Date().addingTimeInterval(1800) {
                    print("🎵 [YTDLPService] Skipping \(videoId) - cached URL valid for \(Int(cached.expiresAt.timeIntervalSinceNow / 60))+ minutes")
                    continue
                }

                group.addTask {
                    do {
                        _ = try await self.getStreamURL(videoId: videoId)
                    } catch {
                        print("⚠️ [YTDLPService] Failed to prefetch \(videoId): \(error.localizedDescription)")
                    }
                }
            }
        }

        print("✅ [YTDLPService] Pre-fetch completed")
    }

    /// Clear expired entries from cache
    func clearExpiredCache() {
        cacheQueue.async {
            let now = Date()
            self.streamCache = self.streamCache.filter { $0.value.expiresAt > now }
            print("🎵 [YTDLPService] Cleared expired cache entries")
        }
    }

    // MARK: - Private Methods

    private func getCachedStream(_ videoId: String) -> CachedStream? {
        cacheQueue.sync {
            return streamCache[videoId]
        }
    }

    private func cacheStream(videoId: String, url: URL, expiresAt: Date) {
        cacheQueue.async {
            self.streamCache[videoId] = CachedStream(url: url, expiresAt: expiresAt)
        }
    }
}
