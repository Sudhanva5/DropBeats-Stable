import Foundation
import Network
import CryptoKit

private extension String {
    func sha1() -> String {
        let data = Data(self.utf8)
        let hash = Insecure.SHA1.hash(data: data)
        return Data(hash).base64EncodedString()
    }
}

class WebSocketManager: ObservableObject {
    static let shared = WebSocketManager()
    
    private var server: NWListener?
    private var activeConnection: NWConnection?
    private let port: UInt16 = 8089
    private let queue = DispatchQueue(label: "com.sudhanva.dropbeat.websocket")
    
    private var reconnectAttempts: Int = 0
    private let INITIAL_RECONNECT_DELAY: TimeInterval = 1.0
    private let MAX_RECONNECT_DELAY: TimeInterval = 60.0
    private var lastPongReceived: Date = Date()
    private let PING_INTERVAL: TimeInterval = 5.0
    private let PONG_TIMEOUT: TimeInterval = 15.0
    
    @Published private(set) var isConnected = false
    @Published private(set) var currentTrack: Track?
    @Published private(set) var recentTracks: [Track] = []
    
    // Replace Timer with DispatchWorkItem for debouncing
    private var pendingTrackUpdate: DispatchWorkItem?
    private var reconnectTimer: DispatchWorkItem?
    
    private init() {
        print("🎵 [DropBeat] Initializing WebSocket Manager...")
        setupServer()
        startPingInterval()
    }
    
    private func setupServer() {
        do {
            print("🎵 [DropBeat] Setting up WebSocket server on port \(port)...")
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.allowLocalEndpointReuse = true
            
            let nwPort = NWEndpoint.Port(rawValue: port)!
            server = try NWListener(using: parameters, on: nwPort)
            
            server?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("✅ [DropBeat] Server ready on port \(self?.port ?? 0)")
                    DispatchQueue.main.async {
                        self?.isConnected = true
                        self?.handleConnectionChange()
                    }
                case .failed(let error):
                    print("❌ [DropBeat] Server failed: \(error)")
                    self?.handleServerFailure()
                case .cancelled:
                    print("🔴 [DropBeat] Server cancelled")
                    DispatchQueue.main.async {
                        self?.isConnected = false
                        self?.handleConnectionChange()
                    }
                default:
                    print("ℹ️ [DropBeat] Server state: \(state)")
                }
            }
            
            server?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            print("🎵 [DropBeat] Starting server...")
            server?.start(queue: queue)
            
        } catch {
            print("❌ [DropBeat] Failed to create server: \(error)")
            handleServerFailure()
        }
    }
    
    private func startPingInterval() {
        queue.asyncAfter(deadline: .now() + PING_INTERVAL) { [weak self] in
            guard let self = self else { return }

            // Only check connection if we have an active connection
            if self.activeConnection != nil {
                self.checkConnection()
            }

            // Continue ping interval if we're still running
            // This prevents indefinite recursion if server is nil
            if self.server != nil {
                self.startPingInterval()
            } else {
                print("⏰ [DropBeat] Stopping ping interval - server is nil")
            }
        }
    }
    
    private func checkConnection() {
        let timeSinceLastPong = Date().timeIntervalSince(lastPongReceived)
        if timeSinceLastPong > PONG_TIMEOUT {
            print("⚠️ [DropBeat] Connection seems dead, last pong was \(timeSinceLastPong) seconds ago")
            // Only handle failure if we have an active connection to fail
            if let connection = activeConnection {
                handleConnectionFailure(connection)
            }
        }
    }
    
    private func handleServerFailure() {
        // Cancel existing connections first
        activeConnection?.cancel()
        activeConnection = nil
        
        // Cancel server and wait for it to clean up
        if let existingServer = server {
            existingServer.cancel()
            server = nil
            
            // Wait a bit before attempting to restart
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Update UI state
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.handleConnectionChange()
        }
        
        // Cancel any existing reconnect timer
        reconnectTimer?.cancel()
        
        // Calculate delay with exponential backoff, capped at max delay
        let delay = min(
            INITIAL_RECONNECT_DELAY * pow(2.0, Double(reconnectAttempts)),
            MAX_RECONNECT_DELAY
        )
        
        reconnectAttempts += 1
        print("🔄 [DropBeat] Scheduling reconnect attempt \(reconnectAttempts) in \(delay) seconds")
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Only attempt restart if we're not already connected
            if self.server == nil && self.activeConnection == nil {
                print("🔄 [DropBeat] Attempting server restart...")
                self.setupServer()
            }
        }
        
        reconnectTimer = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("🔵 [DropBeat] New connection attempt")
        
        // If we have an active connection, close it
        if let existingConnection = activeConnection {
            print("⚠️ [DropBeat] Closing existing connection")
            existingConnection.cancel()
            activeConnection = nil
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .preparing:
                print("ℹ️ [DropBeat] Connection state: preparing")
            case .ready:
                print("✅ [DropBeat] Connection ready")
                self?.setupReceive(for: connection)
                self?.activeConnection = connection
                DispatchQueue.main.async {
                    self?.isConnected = true
                    self?.handleConnectionChange()
                }
            case .failed(let error):
                print("❌ [DropBeat] Connection failed: \(error)")
                self?.handleConnectionFailure(connection)
            case .cancelled:
                print("🔴 [DropBeat] Connection cancelled")
                self?.handleConnectionFailure(connection)
            case .waiting(let error):
                print("⏳ [DropBeat] Connection waiting: \(error)")
            default:
                print("ℹ️ [DropBeat] Connection state: \(state)")
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func handleConnectionFailure(_ connection: NWConnection) {
        if connection === activeConnection {
            print("🔌 [DropBeat] Active connection lost")
            activeConnection = nil
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = false
                self?.handleConnectionChange()
            }
        }
        connection.cancel()
    }
    
    private func handleConnectionChange() {
        NotificationCenter.default.post(
            name: NSNotification.Name("WebSocketConnectionChanged"),
            object: nil,
            userInfo: ["isConnected": isConnected]
        )
    }
    
    private func setupReceive(for connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("❌ [DropBeat] Receive error:", error)
                self?.handleConnectionFailure(connection)
                return
            }
            
            if let data = data {
                print("📥 [DropBeat] Raw data received:", data.count, "bytes")
                print("📥 [DropBeat] Raw bytes:", data.map { String(format: "%02x", $0) }.joined(separator: " "))
                
                // Add this debug print
                print("🔍 About to decode WebSocket frame...")
                
                // If it's a GET request, handle it as a WebSocket upgrade
                if let str = String(data: data, encoding: .utf8), str.hasPrefix("GET") {
                    print("👋 Handling as WebSocket handshake")
                    self?.handleWebSocketHandshake(str, connection: connection)
                } else {
                    print("📦 Handling as WebSocket frame")
                    if let decodedData = self?.decodeWebSocketFrame(data) {
                        print("✅ Frame decoded successfully")
                        self?.handleMessage(decodedData)
                    } else {
                        print("❌ Frame decoding failed")
                    }
                }
            }
            
            if !isComplete {
                self?.setupReceive(for: connection)
            }
        }
    }
    
    private func handleWebSocketHandshake(_ request: String, connection: NWConnection) {
        print("🤝 [DropBeat] Processing handshake request:\n\(request)")
        
        // Split request into lines and extract headers
        let requestLines = request.components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        
        for line in requestLines {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        // Check for required WebSocket headers
        guard let websocketKey = headers["Sec-WebSocket-Key"] else {
            print("❌ [DropBeat] Missing Sec-WebSocket-Key header")
            handleConnectionFailure(connection)
            return
        }
        
        // Generate WebSocket accept key
        let magicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let acceptKey = (websocketKey + magicString).sha1()
        
        // Construct response with proper headers
        let response = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(acceptKey)",
            "",
            ""  // Empty line at the end is required
        ].joined(separator: "\r\n")
        
        print("🤝 [DropBeat] Sending handshake response:\n\(response)")
        
        // Send handshake response
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("❌ [DropBeat] Handshake failed: \(error)")
                self?.handleConnectionFailure(connection)
            } else {
                print("✅ [DropBeat] Handshake successful")
                self?.lastPongReceived = Date()
            }
        })
    }
    
    private func handleMessage(_ data: Data) {
        if let str = String(data: data, encoding: .utf8) {
            print("📝 [DropBeat] Message:", str)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                
                print("📦 [DropBeat] Message type:", type)
                
                switch type {
                case "PING":
                    print("🏓 [DropBeat] Got PING, sending PONG")
                    sendResponse(["type": "PONG", "timestamp": Date().timeIntervalSince1970])
                    lastPongReceived = Date()
                    
                case "TRACK_INFO":
                    if let trackData = json["data"] as? [String: Any],
                       let trackJson = try? JSONSerialization.data(withJSONObject: trackData),
                       let track = try? JSONDecoder().decode(Track.self, from: trackJson) {
                        print("🎵 [DropBeat] Received track info - ID:", track.id, "Title:", track.title)
                        
                        // Cancel any pending update
                        pendingTrackUpdate?.cancel()
                        
                        // Create new work item for the update
                        let workItem = DispatchWorkItem { [weak self] in
                            guard let self = self else { 
                                print("❌ [DropBeat] Self was deallocated during track update")
                                return 
                            }
                            
                            print("⏳ [DropBeat] Processing track update on thread:", Thread.current.description)
                            
                            DispatchQueue.main.async {
                                print("🔄 [DropBeat] On main thread, current track:", self.currentTrack?.title ?? "nil")
                                print("📥 [DropBeat] New track:", track.title)
                                
                                // Only update if track info has actually changed
                                if self.currentTrack?.id != track.id || 
                                   self.currentTrack?.isPlaying != track.isPlaying ||
                                   abs((self.currentTrack?.currentTime ?? 0) - track.currentTime) > 1 {
                                    
                                    print("✨ [DropBeat] Track info changed, updating UI")
                                    self.currentTrack = track
                                    print("✅ [DropBeat] Track info updated to:", track.title)
                                    
                                    // Add to recent tracks if it's a new track
                                    if !(self.recentTracks.contains { $0.id == track.id }) {
                                        print("📝 [DropBeat] Adding to recent tracks:", track.title)
                                        self.recentTracks.insert(track, at: 0)
                                        if self.recentTracks.count > 7 {
                                            self.recentTracks.removeLast()
                                        }
                                    }
                                    
                                    // Post notification after state is updated
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("TrackChanged"),
                                        object: nil,
                                        userInfo: ["track": track]
                                    )
                                    print("📢 [DropBeat] Posted TrackChanged notification")
                                } else {
                                    print("⏭️ [DropBeat] Track info unchanged, skipping update")
                                }
                            }
                        }
                        
                        // Store and schedule the new work item
                        pendingTrackUpdate = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
                    }
                    
                case "SEARCH_RESULTS":
                    if let data = json["data"] as? [String: Any],
                       let categories = data["categories"] as? [String: [[String: Any]]],
                       let songs = categories["songs"] as? [[String: Any]] {
                        print("🔍 [DropBeat] Received songs:", songs.count)
                        var allResults: [SearchResult] = []
                        var seenIds = Set<String>() // Track seen IDs to avoid duplicates
                        
                        // Process songs
                        let songResults = songs.compactMap { result -> SearchResult? in
                            // Get ID and validate
                            guard let id = result["id"] as? String,
                                  !id.isEmpty else {
                                print("⚠️ [DropBeat] Skipping result: Missing or empty ID")
                                return nil
                            }
                            
                            // Skip if we've seen this ID before
                            guard !seenIds.contains(id) else {
                                print("⚠️ [DropBeat] Skipping duplicate result with ID:", id)
                                return nil
                            }
                            
                            // Get title and validate
                            guard let title = result["title"] as? String,
                                  !title.isEmpty,
                                  title != "Unknown Title" else {
                                print("⚠️ [DropBeat] Skipping result: Invalid title for ID:", id)
                                return nil
                            }
                            
                            // Get artist information
                            let artist = result["artist"] as? String ?? "Unknown Artist"
                            
                            // Add ID to seen set
                            seenIds.insert(id)
                            
                            print("🏷️ [DropBeat] Valid result - ID:", id, "Title:", title, "Artist:", artist)
                            
                            return SearchResult(
                                id: id,
                                title: title,
                                artist: artist,
                                type: .song,
                                thumbnailUrl: result["thumbnailUrl"] as? String
                            )
                        }
                        
                        allResults.append(contentsOf: songResults)
                        print("✅ [DropBeat] Total valid songs:", allResults.count)
                        
                        // Post notification with search results
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SearchResults"),
                            object: nil,
                            userInfo: ["results": allResults]
                        )
                    }
                    
                case "SEARCH_ERROR":
                    if let error = json["error"] as? String,
                       let searchUrl = json["searchUrl"] as? String {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SearchError"),
                            object: nil,
                            userInfo: [
                                "error": error,
                                "searchUrl": searchUrl
                            ]
                        )
                    }
                    
                default:
                    break
                }
            }
        }
    }
    
    private func decodeWebSocketFrame(_ data: Data) -> Data? {
        guard data.count >= 2 else {
            print("�� Frame too small: \(data.count) bytes")
            return nil
        }
        
        let firstByte = data[0]
        let secondByte = data[1]
        let isMasked = (secondByte & 0x80) != 0
        var payloadLength = UInt64(secondByte & 0x7F)
        var currentIndex = 2
        
        // Handle extended payload length
        if payloadLength == 126 {
            guard data.count >= 4 else { return nil }
            payloadLength = UInt64(data[2]) << 8 | UInt64(data[3])
            currentIndex = 4
        } else if payloadLength == 127 {
            guard data.count >= 10 else { return nil }
            payloadLength = 0
            for i in 0..<8 {
                payloadLength = payloadLength << 8 | UInt64(data[2 + i])
            }
            currentIndex = 10
        }
        
        // Get masking key if present
        let maskingKey: [UInt8]?
        if isMasked {
            guard data.count >= currentIndex + 4 else { return nil }
            maskingKey = Array(data[currentIndex..<currentIndex + 4])
            currentIndex += 4
        } else {
            maskingKey = nil
        }
        
        // Get payload
        guard data.count >= currentIndex + Int(payloadLength) else { return nil }
        var payload = Array(data[currentIndex..<currentIndex + Int(payloadLength)])
        
        // Unmask if necessary
        if let mask = maskingKey {
            for i in 0..<payload.count {
                payload[i] ^= mask[i % 4]
            }
        }
        
        return Data(payload)
    }
    
    private func createWebSocketFrame(withPayload payload: Data) -> Data {
        var frame = Data()
        
        // First byte: FIN bit and opcode for text frame
        frame.append(0x81)  // 1000 0001: FIN=1, Opcode=1 (text)
        
        // Second byte: Payload length and mask bit (no mask for server)
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else if payload.count < 65536 {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(127)
            for i in stride(from: 7, through: 0, by: -1) {
                frame.append(UInt8((payload.count >> (i * 8)) & 0xFF))
            }
        }
        
        // Add payload without masking
        frame.append(payload)
        return frame
    }
    
    private func sendResponse(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else {
            print("❌ [DropBeat] Failed to serialize response")
            return
        }
        
        let frame = createWebSocketFrame(withPayload: data)
        print("📤 [DropBeat] Sending response frame of size: \(frame.count) bytes")
        print("�� [DropBeat] Response content: \(message)")
        
        activeConnection?.send(content: frame, completion: .contentProcessed { error in
            if let error = error {
                print("❌ [DropBeat] Failed to send response: \(error)")
            } else {
                print("✅ [DropBeat] Response sent successfully")
            }
        })
    }
    
    // MARK: - Public Methods
    
    private var playPauseDebouncer: DispatchWorkItem?
    private var isPlayPauseInProgress = false
    
    func togglePlayPause() {
        // Simple command - just like next/previous
        print("⏯️ [DropBeat] Sending play/pause command")
        sendCommand("togglePlayPause")
    }
    
    // Play specific content by ID
    func play(id: String, type: SearchResultType) {
        print("▶️ [DropBeat] Playing content - ID:", id, "Type:", type.rawValue)
        
        let data: [String: Any] = [
            "id": id,
            "type": type.rawValue
        ]
        
        sendCommand("play", data: data)
    }
    
    // Deprecate these in favor of toggle
    func play() {
        togglePlayPause()
    }
    
    func pause() {
        togglePlayPause()
    }
    
    func next() {
        print("⏭️ [DropBeat] Next track")
        sendCommand("next")
    }
    
    func previous() {
        print("⏮️ [DropBeat] Previous track")
        sendCommand("previous")
    }
    
    func toggleLike() {
        print("❤️ [DropBeat] Toggle like")
        sendCommand("toggleLike")
    }
    
    func openYouTubeMusic() {
        print("🎵 [DropBeat] Opening YouTube Music")
        sendCommand("openYouTubeMusic")
    }
    
    func seek(to position: Double) {
        print("⏩ [DropBeat] Seeking to position:", position)
        let roundedPosition = round(position)
        let data: [String: Any] = ["position": roundedPosition]
        print("📤 [DropBeat] Sending seek command with data:", data)
        
        // Send the command
        sendCommand("seek", data: data)
        
        // Update local track info immediately for smoother UI
        if let track = currentTrack {
            let updatedTrack = Track(
                id: track.id,
                title: track.title,
                artist: track.artist,
                albumArt: track.albumArt,
                duration: track.duration,
                isLiked: track.isLiked,
                isPlaying: track.isPlaying,
                currentTime: roundedPosition
            )
            DispatchQueue.main.async { [weak self] in
                self?.currentTrack = updatedTrack
            }
        }
    }
    
    private func sendCommand(_ command: String, data: [String: Any] = [:]) {
        var message: [String: Any] = [
            "type": "COMMAND",
            "command": command
        ]
        
        if !data.isEmpty {
            message["data"] = data
        }
        
        print("📤 [DropBeat] Sending message:", message)
        sendResponse(message)
    }
    
    // MARK: - Command Palette Methods
    
    func search(query: String, onSuccess: @escaping ([SearchResult]) -> Void, onError: @escaping (String, String) -> Void) {
        guard isConnected else {
            onError("NOT_CONNECTED", "https://music.youtube.com/search?q=\(query)")
            return
        }
        
        print("🔍 [DropBeat] Starting search for:", query)
        
        // Get country from AppStateManager with India as default
        let country = AppStateManager.shared.licenseInfo?.country ?? AppStateManager.LicenseInfo.defaultCountry
        
        // Create URL components for the search request
        var components = URLComponents()
        components.scheme = "https"
        components.host = "dropbeats-server.onrender.com"
        components.path = "/search/\(query)"
        components.queryItems = [
            URLQueryItem(name: "country", value: country)
        ]
        
        guard let url = components.url else {
            onError("INVALID_URL", "https://music.youtube.com/search?q=\(query)")
            return
        }
        
        // Make the search request to our server
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ [DropBeat] Search error:", error)
                DispatchQueue.main.async {
                    onError("NETWORK_ERROR", "https://music.youtube.com/search?q=\(query)")
                }
                return
            }
            
            guard let data = data else {
                print("❌ [DropBeat] No data received")
                DispatchQueue.main.async {
                    onError("NO_DATA", "https://music.youtube.com/search?q=\(query)")
                }
                return
            }
            
            do {
                // First, print raw response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📥 [DropBeat] Raw search response:", jsonString)
                }
                
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
                
                let response = try JSONDecoder().decode(SearchResponse.self, from: data)
                print("📊 [DropBeat] Decoded response - Total items:", response.total)
                
                // Debug print each category's count
                print("🔢 [DropBeat] Category counts:")
                print("   Songs:", response.categories.songs?.count ?? 0)
                print("   Albums:", response.categories.albums?.count ?? 0)
                print("   Playlists:", response.categories.playlists?.count ?? 0)
                print("   Videos:", response.categories.videos?.count ?? 0)
                print("   Podcasts:", response.categories.podcasts?.count ?? 0)
                print("   Episodes:", response.categories.episodes?.count ?? 0)
                
                let allResults = [
                    response.categories.songs,
                    response.categories.albums,
                    response.categories.playlists,
                    response.categories.videos,
                    response.categories.podcasts,
                    response.categories.episodes
                ].compactMap { $0 }.flatMap { $0 }
                
                print("✅ [DropBeat] Total results after processing:", allResults.count)
                print("📊 [DropBeat] Results by type:", Dictionary(grouping: allResults, by: { $0.type.rawValue }).mapValues { $0.count })
                
                DispatchQueue.main.async {
                    onSuccess(allResults)
                }
            } catch {
                print("❌ [DropBeat] JSON decode error:", error)
                // Print the raw data for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 [DropBeat] Failed to decode JSON:", jsonString)
                }
                DispatchQueue.main.async {
                    onError("DECODE_ERROR", "https://music.youtube.com/search?q=\(query)")
                }
            }
        }.resume()
    }
    
    // Add this new method for custom commands
    func send(command type: String) async throws {
        let message: [String: Any] = [
            "type": "COMMAND",
            "command": type
        ]
        
        print("📤 [DropBeat] Sending custom command:", type)
        sendResponse(message)
    }
}
