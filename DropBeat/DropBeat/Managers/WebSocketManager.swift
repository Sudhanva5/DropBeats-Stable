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
    private var lastPongReceived: Date = Date()
    private let PING_INTERVAL: TimeInterval = 5.0
    
    @Published var isConnected = false
    @Published var currentTrack: Track?
    @Published var recentTracks: [Track] = []
    
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
            if self.server != nil {
                self.startPingInterval()
            }
        }
    }
    
    private func checkConnection() {
        let timeSinceLastPong = Date().timeIntervalSince(lastPongReceived)
        if timeSinceLastPong > PING_INTERVAL * 2 {
            print("⚠️ [DropBeat] Connection seems dead, last pong was \(timeSinceLastPong) seconds ago")
            handleConnectionFailure(activeConnection!)
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
        
        // Schedule restart with exponential backoff
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0)
        
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            
            // Only attempt restart if we're not already connected
            if self.server == nil && self.activeConnection == nil {
                print("🔄 [DropBeat] Attempting server restart...")
                self.setupServer()
            }
        }
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
                        DispatchQueue.main.async { [weak self] in
                            self?.currentTrack = track
                            // Add track to recent tracks if it's not already there
                            if !(self?.recentTracks.contains { $0.id == track.id } ?? false) {
                                print("📝 [DropBeat] Adding track to recent tracks - ID:", track.id)
                                self?.recentTracks.insert(track, at: 0)
                                // Keep only the last 10 tracks
                                if self?.recentTracks.count ?? 0 > 10 {
                                    self?.recentTracks.removeLast()
                                }
                                print("📋 [DropBeat] Recent tracks updated, count:", self?.recentTracks.count ?? 0)
                            }
                            NotificationCenter.default.post(
                                name: NSNotification.Name("TrackChanged"),
                                object: nil,
                                userInfo: ["track": track]
                            )
                        }
                    }
                    
                case "SEARCH_RESULTS":
                    if let resultsData = json["data"] as? [[String: Any]] {
                        let results = resultsData.map { result -> SearchResult in
                            SearchResult(
                                id: result["id"] as? String ?? "",
                                title: result["title"] as? String ?? "",
                                artist: result["artist"] as? String ?? "",
                                type: SearchResultType(rawValue: result["type"] as? String ?? "") ?? .song,
                                thumbnailUrl: result["thumbnailUrl"] as? String
                            )
                        }
                        // Post notification with search results
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SearchResults"),
                            object: nil,
                            userInfo: ["results": results]
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
            print("❌ Frame too small: \(data.count) bytes")
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
        print("📤 [DropBeat] Response content: \(message)")
        
        activeConnection?.send(content: frame, completion: .contentProcessed { error in
            if let error = error {
                print("❌ [DropBeat] Failed to send response: \(error)")
            } else {
                print("✅ [DropBeat] Response sent successfully")
            }
        })
    }
    
    // MARK: - Public Methods
    
    func next() {
        print("⏭️ [DropBeat] Next track")
        sendCommand("next")
    }
    
    func previous() {
        print("⏮️ [DropBeat] Previous track")
        sendCommand("previous")
    }
    
    func play(id: String? = nil, type: SearchResultType = .song) {
        print("▶️ [DropBeat] Play", id ?? "current track")
        if let id = id {
            print("🎯 [DropBeat] Playing specific track with ID:", id)
            let message: [String: Any] = [
                "type": "COMMAND",
                "command": "play",
                "data": [
                    "id": id,
                    "type": type.rawValue
                ]
            ]
            print("📤 [DropBeat] Sending play command with data:", message)
            sendResponse(message)
        } else {
            print("▶️ [DropBeat] Playing/pausing current track")
            sendCommand("play")
        }
    }
    
    func pause() {
        print("⏸️ [DropBeat] Pause")
        sendCommand("pause")
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
        
        // Create URL components for the search request
        var components = URLComponents()
        components.scheme = "http"
        components.host = "localhost"
        components.port = 8000
        components.path = "/search/\(query)"
        
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
                // Parse the nested response structure
                struct SearchResponse: Codable {
                    let categories: Categories
                    
                    struct Categories: Codable {
                        let songs: [SearchResult]
                        
                        enum CodingKeys: String, CodingKey {
                            case songs
                        }
                        
                        init(from decoder: Decoder) throws {
                            let container = try decoder.container(keyedBy: CodingKeys.self)
                            songs = try container.decode([SearchResult].self, forKey: .songs)
                        }
                        
                        func encode(to encoder: Encoder) throws {
                            var container = encoder.container(keyedBy: CodingKeys.self)
                            try container.encode(songs, forKey: .songs)
                        }
                    }
                }
                
                let response = try JSONDecoder().decode(SearchResponse.self, from: data)
                DispatchQueue.main.async {
                    onSuccess(response.categories.songs)
                }
            } catch {
                print("❌ [DropBeat] JSON decode error:", error)
                DispatchQueue.main.async {
                    onError("DECODE_ERROR", "https://music.youtube.com/search?q=\(query)")
                }
            }
        }.resume()
    }
    
    func play(id: String, type: SearchResultType) {
        let message: [String: Any] = [
            "type": "COMMAND",
            "command": "play",
            "data": [
                "id": id,
                "type": type.rawValue
            ]
        ]
        sendResponse(message)
    }
}
