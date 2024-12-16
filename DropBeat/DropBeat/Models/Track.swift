import Foundation

struct Track: Codable, Identifiable {
    let id: String
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