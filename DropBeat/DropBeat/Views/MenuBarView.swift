import SwiftUI

struct MenuBarView: View {
    @ObservedObject private var wsManager = WebSocketManager.shared
    
    var body: some View {
        HStack(spacing: 16) {
            // Album Art
            if let track = wsManager.currentTrack,
               let albumArtURL = track.albumArt {
                AsyncImage(url: URL(string: albumArtURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .cornerRadius(4)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .cornerRadius(4)
                }
            }
            
            // Track Info
            if let track = wsManager.currentTrack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text(track.artist)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: 150, alignment: .leading)
            } else {
                Text("No Track Playing")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            // Playback Controls
            HStack(spacing: 16) {
                Button(action: { wsManager.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 12))
                }
                
                if let track = wsManager.currentTrack {
                    Button(action: {
                        if track.isPlaying {
                            wsManager.pause()
                        } else {
                            wsManager.play()
                        }
                    }) {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                    }
                }
                
                Button(action: { wsManager.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

#Preview {
    MenuBarView()
        .frame(width: 300)
        .background(Color.black)
} 