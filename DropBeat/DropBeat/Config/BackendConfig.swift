import Foundation

/// Configuration for backend API endpoints
struct BackendConfig {
    // MARK: - Backend URLs

    /// Railway server for search/recommendations (ytmusicapi works fine on datacenter IPs)
    private static let searchBaseURL = "https://dropbeats-server-production.up.railway.app"

    /// Local bundled backend server for yt-dlp (YouTube blocks datacenter IPs)
    private static let streamBaseURL = "http://127.0.0.1:4002"

    /// Legacy baseURL for backward compatibility (points to Railway)
    static let baseURL = searchBaseURL

    // MARK: - API Endpoints

    /// Full URL for a given endpoint path
    static func url(for path: String) -> String {
        return "\(searchBaseURL)\(path)"
    }

    // MARK: - Convenience URLs

    static func searchURL(query: String) -> String {
        return "\(searchBaseURL)/search/\(query)"
    }

    static func streamURL(videoId: String) -> String {
        return "\(streamBaseURL)/stream-url/\(videoId)"
    }

    static func watchPlaylistURL(videoId: String) -> String {
        return "\(searchBaseURL)/watch-playlist/\(videoId)"
    }

    static func songInfoURL(videoId: String) -> String {
        return "\(streamBaseURL)/song-info/\(videoId)"
    }

    // MARK: - Configuration Info

    /// Print current configuration (useful for debugging)
    static func printConfig() {
        print("🌐 [BackendConfig] Search/Recommendations: \(searchBaseURL)")
        print("🌐 [BackendConfig] Stream URLs (yt-dlp): \(streamBaseURL)")
    }
}
