import Foundation

struct Track: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let albumArt: String?
    var isLiked: Bool
    let duration: Double
    let isPlaying: Bool
    let currentTime: Double
    
    static let empty = Track(
        id: "empty",
        title: "No Track Playing",
        artist: "No Artist",
        albumArt: nil,
        isLiked: false,
        duration: 0,
        isPlaying: false,
        currentTime: 0
    )
    
    init(id: String = UUID().uuidString, title: String, artist: String, albumArt: String?, isLiked: Bool, duration: Double, isPlaying: Bool, currentTime: Double) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumArt = albumArt
        self.isLiked = isLiked
        self.duration = duration
        self.isPlaying = isPlaying
        self.currentTime = currentTime
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, artist, albumArt, isLiked, duration, isPlaying, currentTime
    }
}

// MARK: - Helper extensions
extension Track {
    var formattedDuration: String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedCurrentTime: String {
        let minutes = Int(currentTime / 60)
        let seconds = Int(currentTime.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
} 