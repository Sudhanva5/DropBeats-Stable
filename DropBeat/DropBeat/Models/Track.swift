import Foundation

struct Track: Codable, Identifiable {
    let id: String?
    let title: String
    let artist: String
    let albumArt: String?
    let duration: TimeInterval
    let isLiked: Bool
    let isPlaying: Bool
    let currentTime: TimeInterval
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artist
        case albumArt = "albumArtUrl"
        case duration
        case isLiked
        case isPlaying
        case currentTime
    }
    
    static let empty = Track(
        id: "empty",
        title: "No Track Playing",
        artist: "No Artist",
        albumArt: nil,
        duration: 0,
        isLiked: false,
        isPlaying: false,
        currentTime: 0
    )
}

// Custom Equatable implementation to handle null IDs
extension Track: Equatable {
    static func == (lhs: Track, rhs: Track) -> Bool {
        // If both IDs are present, compare them
        if let lhsId = lhs.id, let rhsId = rhs.id {
            return lhsId == rhsId
        }
        
        // If IDs are nil or different, compare other relevant fields
        return lhs.title == rhs.title &&
               lhs.artist == rhs.artist &&
               lhs.isPlaying == rhs.isPlaying &&
               abs(lhs.currentTime - rhs.currentTime) < 1 // Allow 1 second difference
    }
} 