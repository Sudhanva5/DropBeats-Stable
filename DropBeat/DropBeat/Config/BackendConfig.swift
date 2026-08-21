import Foundation

/// Configuration for backend API endpoints
struct BackendConfig {
    // MARK: - Backend URLs

    /// Cloudflare Worker fronting the Railway backend.
    ///
    /// Everything the app fetches over the network goes through here, and it is
    /// not optional: Jio blocks Railway, so calling
    /// dropbeats-server-production.up.railway.app directly leaves search,
    /// autoplay and licensing dead for those users. The Worker is a plain
    /// reverse proxy — same paths, same payloads, just a reachable address.
    ///
    /// Cloudflare sets CF-Connecting-IP on the way through, which is how the
    /// backend still tells clients apart for rate limiting.
    private static let proxyBaseURL = "https://dropbeats-webhook-proxy.llm-experiments.workers.dev"

    /// Search and recommendations (ytmusicapi), via the proxy.
    private static let searchBaseURL = proxyBaseURL

    /// Licensing, via the same proxy.
    private static let licenseBaseURL = proxyBaseURL

    /// Local bundled backend server for yt-dlp (YouTube blocks datacenter IPs).
    /// Loopback, so no proxy involved and none possible.
    private static let streamBaseURL = "http://127.0.0.1:4002"

    /// Legacy baseURL for backward compatibility
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

    static func licenseURL(path: String) -> String {
        return "\(licenseBaseURL)\(path)"
    }

    static func healthURL() -> String {
        return "\(searchBaseURL)/health"
    }

    // MARK: - Configuration Info

    /// Print current configuration (useful for debugging)
    static func printConfig() {
        print("🌐 [BackendConfig] Search/Recommendations: \(searchBaseURL)")
        print("🌐 [BackendConfig] Licensing: \(licenseBaseURL)")
        print("🌐 [BackendConfig] Stream URLs (yt-dlp): \(streamBaseURL)")
    }
}
