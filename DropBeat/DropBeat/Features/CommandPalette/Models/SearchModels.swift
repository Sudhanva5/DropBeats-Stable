import Foundation

struct SearchResult: Identifiable {
    let id: String
    let title: String
    let artist: String
    let type: ResultType
    let thumbnailUrl: String?
    
    enum ResultType: String, Codable {
        case song
        case album
        case playlist
    }
}

struct SearchSection: Identifiable {
    let id: String
    let title: String
    let results: [SearchResult]
}

struct SearchError: Identifiable {
    let id = UUID()
    let message: String
    let searchUrl: String
} 