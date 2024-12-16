import Foundation

enum SearchResultType: String, Codable {
    case song
    case album
    case playlist
    
    var iconName: String {
        switch self {
        case .song: return "music.note"
        case .album: return "square.stack"
        case .playlist: return "music.note.list"
        }
    }
}

struct SearchResult: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artist: String
    let type: SearchResultType
    let thumbnailUrl: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

struct SearchSection: Identifiable {
    let id: String
    let title: String
    let results: [SearchResult]
}

struct SearchError {
    let message: String
    let searchUrl: String
} 