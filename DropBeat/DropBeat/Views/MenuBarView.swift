import SwiftUI

struct MenuBarView: View {
    @StateObject private var wsManager = WebSocketManager.shared
    @State private var seekPosition: Double = 0
    @State private var isSeeking = false
    @State private var seekDebounceWorkItem: DispatchWorkItem?
    
    var body: some View {
        MenuBarContent(
            wsManager: wsManager,
            seekPosition: $seekPosition,
            isSeeking: $isSeeking,
            onSeek: handleSeek
        )
        .onAppear {
            print("🎵 [MenuBarView] View appeared")
            print("🎵 [MenuBarView] Initial track:", wsManager.currentTrack?.title ?? "nil")
        }
    }
    
    private func handleSeek(_ position: Double) {
        // Cancel any pending seek operation
        seekDebounceWorkItem?.cancel()
        
        // Create a new debounced work item
        let workItem = DispatchWorkItem { [weak wsManager] in
            wsManager?.seek(to: position)
        }
        
        // Store the work item and schedule it
        seekDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var wsManager: WebSocketManager
    @Binding var seekPosition: Double
    @Binding var isSeeking: Bool
    var onSeek: (Double) -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            albumArtView
            VStack(spacing: 4) {
                trackInfoView
                if let track = wsManager.currentTrack {
                    // Time scrubber
                    Scrubber(
                        value: Binding(
                            get: { isSeeking ? seekPosition : track.currentTime },
                            set: { newValue in
                                seekPosition = newValue
                                isSeeking = true
                                onSeek(newValue)
                            }
                        ),
                        isSeeking: $isSeeking,
                        duration: track.duration,
                        currentTime: track.currentTime
                    )
                }
            }
            playbackControlsView
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onChange(of: wsManager.currentTrack) { track in
            print("🔄 [MenuBarContent] Track changed")
            print("📝 [MenuBarContent] New track title:", track?.title ?? "nil")
            print("🎵 [MenuBarContent] New track artist:", track?.artist ?? "nil")
            print("🖼️ [MenuBarContent] New album art URL:", track?.albumArt ?? "nil")
            print("▶️ [MenuBarContent] Is playing:", track?.isPlaying ?? false)
            print("⏱️ [MenuBarContent] Current time:", track?.currentTime ?? 0)
            print("⏳ [MenuBarContent] Duration:", track?.duration ?? 0)
        }
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
                        .onAppear {
                            print("🖼️ [MenuBarContent] Loading album art from:", url)
                        }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .cornerRadius(4)
                        .onAppear {
                            print("✅ [MenuBarContent] Album art loaded successfully")
                        }
                case .failure(let error):
                    placeholderRect(color: .red)
                        .onAppear {
                            print("❌ [MenuBarContent] Failed to load album art:", error)
                            print("🔗 URL was:", url)
                        }
                @unknown default:
                    placeholderRect(color: .gray)
                }
            }
        } else {
            placeholderRect(color: .gray)
                .onAppear {
                    print("ℹ️ [MenuBarContent] No album art URL available")
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
            .onAppear {
                print("📝 [MenuBarContent] Showing track info - Title:", track.title)
            }
        } else {
            Text("No Track Playing")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .onAppear {
                    print("ℹ️ [MenuBarContent] Showing 'No Track Playing' state")
                }
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
        Button(action: { 
            print("⏮️ [MenuBarContent] Previous button tapped")
            wsManager.previous() 
        }) {
            Image(systemName: "backward.fill")
                .font(.system(size: 12))
        }
    }
    
    @ViewBuilder
    private var playPauseButton: some View {
        if let track = wsManager.currentTrack {
            Button(action: {
                print("⏯️ [MenuBarContent] Play/Pause button tapped, current state:", track.isPlaying ? "playing" : "paused")
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
        Button(action: { 
            print("⏭️ [MenuBarContent] Next button tapped")
            wsManager.next() 
        }) {
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

private struct Scrubber: View {
    @Binding var value: Double
    @Binding var isSeeking: Bool
    let duration: Double
    let currentTime: Double
    @State private var isDragging = false
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 2)
                
                // Progress track
                let progress = currentTime / max(duration, 1)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: max(0, min(CGFloat(progress) * geometry.size.width, geometry.size.width)), height: 2)
                
                // Handle
                let handleProgress = (isDragging || isSeeking ? value : currentTime) / max(duration, 1)
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .offset(x: max(0, min(CGFloat(handleProgress) * (geometry.size.width - 8), geometry.size.width - 8)))
                    .offset(y: -3)
                    .opacity(isHovering || isDragging ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: isHovering)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        isSeeking = true
                        let percentage = max(0, min(gesture.location.x / geometry.size.width, 1))
                        value = percentage * duration
                    }
                    .onEnded { _ in
                        isDragging = false
                        isSeeking = false
                    }
            )
            .onHover { hovering in
                withAnimation {
                    isHovering = hovering
                }
            }
        }
        .frame(height: 16)
    }
} 
