import SwiftUI

struct CompactScrubber: View {
    @Binding var value: Double
    @Binding var isSeeking: Bool
    let duration: Double
    let currentTime: Double
    let isEnabled: Bool
    @State private var isDragging = false
    @State private var lastSentValue: Double = 0
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Invisible larger hit area
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { gesture in
                                    if isEnabled {
                                        let percentage = gesture.location.x / geometry.size.width
                                        let newValue = max(0, min(percentage * duration, duration))
                                        value = newValue
                                        print("🎵 [Scrubber] Click seek to: \(newValue)")
                                        isSeeking = true
                                        sendSeekCommand(newValue)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            isSeeking = false
                                        }
                                    }
                                }
                        )
                    
                    // Visible elements centered in the hit area
                    VStack {
                        Spacer()
                        
                        // Track and handle container
                        ZStack(alignment: .leading) {
                            // Background track
                            Rectangle()
                                .fill(Color.black.opacity(0.12))
                                .frame(height: 3)
                            
                            // Progress track
                            let progress = currentTime / max(duration, 1)
                            Rectangle()
                                .fill(Color.white.opacity(0.95))
                                .frame(width: max(0, min(CGFloat(progress) * geometry.size.width, geometry.size.width)), height: 3)
                            
                            // Handle
                            let handleProgress = (isDragging || isSeeking ? value : currentTime) / max(duration, 1)
                            Circle()
                                .fill(Color.white.opacity(0.95))
                                .frame(width: 12, height: 12)
                                .offset(x: max(0, min(CGFloat(handleProgress) * (geometry.size.width - 12), geometry.size.width - 12)))
                                .offset(y: -1)
                                .opacity(isHovering || isDragging ? 1 : 0)
                                .animation(.easeOut(duration: 0.3), value: isHovering)
                                .gesture(
                                    DragGesture()
                                        .onChanged { gesture in
                                            if isEnabled {
                                                isDragging = true
                                                isSeeking = true
                                                let percentage = max(0, min(gesture.location.x / geometry.size.width, 1))
                                                let newValue = percentage * duration
                                                value = newValue
                                                
                                                if abs(newValue - lastSentValue) > 1.0 {
                                                    print("🎵 [Scrubber] Dragging to: \(newValue)")
                                                    lastSentValue = newValue
                                                    sendSeekCommand(newValue)
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            if isEnabled {
                                                isDragging = false
                                                isSeeking = false
                                                print("🎵 [Scrubber] Final seek to: \(value)")
                                                sendSeekCommand(value)
                                            }
                                        }
                                )
                        }
                        .frame(height: 12)
                        
                        Spacer()
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.3)) {
                        isHovering = hovering
                    }
                }
                .contentShape(Rectangle())
            }
            .frame(height: 24)
            
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(duration))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
    
    private func sendSeekCommand(_ position: Double) {
        let roundedPosition = round(position)
        print("🎵 [Scrubber] Sending seek command: \(roundedPosition)")
        NotificationCenter.default.post(
            name: NSNotification.Name("SeekCompleted"),
            object: nil,
            userInfo: ["position": roundedPosition]
        )
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ContentView: View {
    @StateObject private var wsManager = WebSocketManager.shared
    @State private var seekPosition: Double = 0
    @State private var isSeeking: Bool = false
    @State private var rotationAngle: Double = 0
    @State private var scaleAmount: CGFloat = 1.0
    
    var body: some View {
        ZStack(alignment: .top) {
            // Main Content first (to establish size)
            VStack(spacing: 0) {
                // Main content
                VStack(spacing: 6) {
                    if !wsManager.isConnected {
                        // Connection Error State
                        VStack(spacing: 8) {
                            Text("Check if Chrome extension is installed")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Text("Please refresh the extension from Chrome")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    } else if let track = wsManager.currentTrack {
                        // Now Playing View
                        HStack(spacing: 10) {
                            // Album Art
                            if let albumArtURL = track.albumArt {
                                AsyncImage(url: URL(string: albumArtURL)) { image in
                                    image
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48)
                                        .cornerRadius(4)
                                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 48, height: 48)
                                        .cornerRadius(4)
                                }
                            }
                            
                            // Track Info
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                Text(track.artist)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        
                        // Time Scrubber
                        CompactScrubber(
                            value: Binding(
                                get: { isSeeking ? seekPosition : track.currentTime },
                                set: { newValue in
                                    print("🎵 Slider value changed to: \(newValue)")
                                    seekPosition = newValue
                                }
                            ),
                            isSeeking: $isSeeking,
                            duration: track.duration,
                            currentTime: track.currentTime,
                            isEnabled: true
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                        
                        // Playback Controls
                        HStack(spacing: 20) {
                            Button(action: { wsManager.previous() }) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 16))
                            }
                            
                            Button(action: { wsManager.togglePlayPause() }) {
                                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 20))
                            }
                            
                            Button(action: { wsManager.next() }) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 16))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 0)
                        .padding(.bottom, 16)
                    } else {
                        // No Track Playing State
                        VStack(spacing: 6) {
                            Text("No Track Playing")
                                .font(.system(size: 13, weight: .medium))
                            
                            Button(action: { wsManager.openYouTubeMusic() }) {
                                Text("Open YouTube Music")
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                }
                
                // Bottom Bar
                HStack {
                    // Search Button
                    Button(action: {
                        CommandPalette.shared.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Settings Button
                    Button(action: {
                        // TODO: Implement settings action
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Rectangle()
                        .fill(.thinMaterial)
                        .overlay(
                            Rectangle()
                                .frame(height: 0.5)
                                .foregroundColor(Color.primary.opacity(0.1)),
                            alignment: .top
                        )
                )
            }
            .background {
                // Background layers inside background modifier
                ZStack {
                    if let track = wsManager.currentTrack,
                       let albumArtURL = track.albumArt {
                        AsyncImage(url: URL(string: albumArtURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 20)
                                .opacity(0.7)
                                .modifier(RotatingModifier())
                                .scaleEffect(scaleAmount)
                        } placeholder: {
                            Color.clear
                        }
                    }
                    
                    Rectangle()
                        .fill(.ultraThickMaterial)
                        .opacity(0.87)
                }
                .animation(.easeInOut(duration: 0.15), value: wsManager.currentTrack?.id)
            }
        }
        .frame(width: 280)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            setupSeekObserver()
            // Start scale animation
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                scaleAmount = 1.2
            }
        }
    }
    
    private func setupSeekObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SeekCompleted"),
            object: nil,
            queue: .main
        ) { notification in
            if let position = notification.userInfo?["position"] as? Double {
                print("🎵 Seek notification received: \(position)")
                wsManager.seek(to: position)
            }
        }
    }
}

struct RotatingModifier: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(Animation.linear(duration: 20).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

#Preview {
    ContentView()
} 
