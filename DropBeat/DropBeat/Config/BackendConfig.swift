import Foundation

/// Configuration for backend API endpoints
struct BackendConfig {
    // MARK: - Backend URL

    /// Railway production server
    /// TODO: Replace with your actual Railway URL after deployment
    static let baseURL = "https://your-railway-url.up.railway.app"

    // MARK: - API Endpoints

    /// Full URL for a given endpoint path
    static func url(for path: String) -> String {
        return "\(baseURL)\(path)"
    }

    // MARK: - Convenience URLs

    static func searchURL(query: String) -> String {
        return "\(baseURL)/search/\(query)"
    }

    static func streamURL(videoId: String) -> String {
        return "\(baseURL)/stream-url/\(videoId)"
    }

    static func watchPlaylistURL(videoId: String) -> String {
        return "\(baseURL)/watch-playlist/\(videoId)"
    }

    static func songInfoURL(videoId: String) -> String {
        return "\(baseURL)/song-info/\(videoId)"
    }

    // MARK: - Configuration Info

    /// Print current configuration (useful for debugging)
    static func printConfig() {
        print("🌐 [BackendConfig] Base URL: \(baseURL)")
    }
}
