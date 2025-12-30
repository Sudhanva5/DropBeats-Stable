import Foundation

/// Service for fetching detailed song information including accurate duration
class SongInfoService {
    static let shared = SongInfoService()

    private let backendURL = BackendConfig.baseURL
    private var infoCache: [String: CachedSongInfo] = [:]
    private let cacheQueue = DispatchQueue(label: "com.sudhanva.dropbeat.songinfo.cache")

    private struct CachedSongInfo {
        let info: SongInfo
        let fetchedAt: Date
    }

    struct SongInfo: Codable {
        let videoId: String
        let title: String
        let author: String
        let duration: TimeInterval
        let thumbnail: String?
    }

    private init() {}

    /// Get detailed song information including accurate duration
    func getSongInfo(videoId: String) async throws -> SongInfo {
        // Check cache first (cache for 1 hour)
        if let cached = getCachedInfo(videoId),
           Date().timeIntervalSince(cached.fetchedAt) < 3600 {
            print("🎵 [SongInfoService] Using cached info for \(videoId)")
            return cached.info
        }

        // Fetch from backend
        print("🎵 [SongInfoService] Fetching song info for \(videoId)...")

        let url = URL(string: "\(backendURL)/song-info/\(videoId)")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaybackError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            throw PlaybackError.streamURLFetchFailed("Song info fetch failed: HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        let songInfo = try decoder.decode(SongInfo.self, from: data)

        // Cache the info
        cacheInfo(videoId: videoId, info: songInfo)

        print("✅ [SongInfoService] Got song info for \(videoId): \(Int(songInfo.duration / 60)):\(String(format: "%02d", Int(songInfo.duration.truncatingRemainder(dividingBy: 60))))")
        return songInfo
    }

    /// Pre-fetch song info for multiple tracks (parallel)
    func prefetchSongInfo(videoIds: [String]) async {
        print("🎵 [SongInfoService] Pre-fetching info for \(videoIds.count) tracks...")

        await withTaskGroup(of: Void.self) { group in
            for videoId in videoIds {
                // Skip if already cached
                if let cached = getCachedInfo(videoId),
                   Date().timeIntervalSince(cached.fetchedAt) < 3600 {
                    continue
                }

                group.addTask {
                    do {
                        _ = try await self.getSongInfo(videoId: videoId)
                    } catch {
                        print("⚠️ [SongInfoService] Failed to pre-fetch info for \(videoId): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    private func getCachedInfo(_ videoId: String) -> CachedSongInfo? {
        cacheQueue.sync {
            return infoCache[videoId]
        }
    }

    private func cacheInfo(videoId: String, info: SongInfo) {
        cacheQueue.async {
            self.infoCache[videoId] = CachedSongInfo(
                info: info,
                fetchedAt: Date()
            )
        }
    }
}
