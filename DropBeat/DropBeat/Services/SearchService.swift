import Foundation

/// Service for searching tracks via the backend API
class SearchService {
    static let shared = SearchService()

    private let backendURL = "http://localhost:8000"

    private init() {}

    /// Search for tracks using the backend's ytmusicapi integration
    func search(
        query: String,
        country: String = "IN",
        onSuccess: @escaping ([SearchResult]) -> Void,
        onError: @escaping (String, String) -> Void
    ) {
        print("🔍 [SearchService] Starting search for:", query)

        // Create URL with country parameter
        guard let baseURL = URL(string: backendURL) else {
            onError("INVALID_URL", "https://music.youtube.com/search?q=\(query)")
            return
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("search").appendingPathComponent(query), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "country", value: country)
        ]

        guard let url = components.url else {
            onError("INVALID_URL", "https://music.youtube.com/search?q=\(query)")
            return
        }

        // Make HTTP request
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ [SearchService] Search error:", error)
                DispatchQueue.main.async {
                    onError("NETWORK_ERROR", "https://music.youtube.com/search?q=\(query)")
                }
                return
            }

            guard let data = data else {
                print("❌ [SearchService] No data received")
                DispatchQueue.main.async {
                    onError("NO_DATA", "https://music.youtube.com/search?q=\(query)")
                }
                return
            }

            do {
                // Parse the nested response structure
                struct SearchResponse: Codable {
                    struct Categories: Codable {
                        var songs: [SearchResult]?
                        var albums: [SearchResult]?
                        var playlists: [SearchResult]?
                        var videos: [SearchResult]?
                        var podcasts: [SearchResult]?
                        var episodes: [SearchResult]?
                    }

                    let categories: Categories
                    let total: Int
                }

                let decoder = JSONDecoder()
                let searchResponse = try decoder.decode(SearchResponse.self, from: data)

                print("📊 [SearchService] Decoded response - Total items:", searchResponse.total)

                // Flatten all categories into a single array
                let allResults = [
                    searchResponse.categories.songs,
                    searchResponse.categories.albums,
                    searchResponse.categories.playlists,
                    searchResponse.categories.videos,
                    searchResponse.categories.podcasts,
                    searchResponse.categories.episodes
                ].compactMap { $0 }.flatMap { $0 }

                print("✅ [SearchService] Total results after processing:", allResults.count)

                DispatchQueue.main.async {
                    onSuccess(allResults)
                }
            } catch {
                print("❌ [SearchService] JSON decode error:", error)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 [SearchService] Failed to decode JSON:", jsonString.prefix(200))
                }
                DispatchQueue.main.async {
                    onError("DECODE_ERROR", "https://music.youtube.com/search?q=\(query)")
                }
            }
        }.resume()
    }
}
