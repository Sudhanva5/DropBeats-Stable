import SwiftUI

struct MenuBarView: View {
    @ObservedObject private var wsManager = WebSocketManager.shared
    
    var body: some View {
        MenuBarContent(wsManager: wsManager)
    }
}

private struct MenuBarContent: View {
    let wsManager: WebSocketManager
    
    var body: some View {
        HStack(spacing: 16) {
            albumArtView
            trackInfoView
            playbackControlsView
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var albumArtView: some View {
        if let track = wsManager.currentTrack,
           let albumArtURL = track.albumArt,
           let encodedURL = albumArtURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encodedURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholderRect(color: .gray)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .cornerRadius(4)
                case .failure(let error):
                    placeholderRect(color: .red)
                        .onAppear {
                            print("❌ [DropBeat] Failed to load album art:", error)
                            print("🔗 URL was:", url)
                        }
                @unknown default:
                    placeholderRect(color: .gray)
                }
            }
        }
    }
    
    @ViewBuilder
    private var trackInfoView: some View {
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
    }
    
    @ViewBuilder
    private var playbackControlsView: some View {
        HStack(spacing: 16) {
            previousButton
            playPauseButton
            nextButton
        }
        .buttonStyle(.plain)
    }
    
    private var previousButton: some View {
        Button(action: { wsManager.previous() }) {
            Image(systemName: "backward.fill")
                .font(.system(size: 12))
        }
    }
    
    @ViewBuilder
    private var playPauseButton: some View {
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
    }
    
    private var nextButton: some View {
        Button(action: { wsManager.next() }) {
            Image(systemName: "forward.fill")
                .font(.system(size: 12))
        }
    }
    
    private func placeholderRect(color: Color) -> some View {
        Rectangle()
            .fill(color.opacity(0.2))
            .frame(width: 40, height: 40)
            .cornerRadius(4)
    }
} 