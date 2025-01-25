import Foundation
import AppKit

final class SearchServerKeepAlive {
    private var timer: Timer?
    private let serverURL: URL
    private let pingInterval: TimeInterval = 840 // 14 minutes
    private var lastPingTime: Date?
    private var lastSuccessfulPingTime: Date?
    
    static let shared = SearchServerKeepAlive()
    
    private init() {
        self.serverURL = URL(string: "https://dropbeats-server.onrender.com/health")!
        setupObservers()
        startPinging()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }
    
    private func startPinging() {
        print("🚀 Starting server ping routine")
        pingServer() // Initial ping
        
        // Create a more reliable timer
        timer = Timer(fire: Date().addingTimeInterval(pingInterval),
                     interval: pingInterval,
                     repeats: true) { [weak self] _ in
            self?.pingServer()
        }
        
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .default)
        }
    }
    
    @objc private func handleWake() {
        print("💻 System woke up, checking last ping time...")
        
        // If last ping was more than interval ago, ping immediately
        if let lastPing = lastPingTime,
           Date().timeIntervalSince(lastPing) > pingInterval {
            pingServer()
        }
        
        // Restart timer to ensure proper timing
        restartTimer()
    }
    
    @objc private func handleSleep() {
        print("💤 System going to sleep, cleaning up timer")
        timer?.invalidate()
        timer = nil
    }
    
    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        startPinging()
    }
    
    @objc private func pingServer() {
        lastPingTime = Date()
        print("📍 Pinging server... (Last success: \(formatLastSuccess()))")
        
        let task = URLSession.shared.dataTask(with: serverURL) { [weak self] _, response, error in
            if let error = error {
                print("❌ Server ping failed: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    self?.lastSuccessfulPingTime = Date()
                    print("✅ Server ping successful")
                } else {
                    print("⚠️ Server responded with status: \(httpResponse.statusCode)")
                }
            }
        }
        task.resume()
    }
    
    private func formatLastSuccess() -> String {
        guard let lastSuccess = lastSuccessfulPingTime else {
            return "Never"
        }
        
        let minutes = Int(-lastSuccess.timeIntervalSinceNow / 60)
        return "\(minutes) minutes ago"
    }
    
    func cleanup() {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        timer = nil
        print("🛑 Stopped server ping routine")
    }
    
    deinit {
        cleanup()
    }
} 
