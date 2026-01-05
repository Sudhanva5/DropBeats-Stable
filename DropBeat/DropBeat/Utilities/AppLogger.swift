import Foundation
import AppKit

/// Centralized logging utility for DropBeat
/// Writes logs to both console and file at ~/Library/Logs/DropBeat/app.log
class AppLogger {
    static let shared = AppLogger()

    private let logFileURL: URL
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.dropbeat.logger", qos: .utility)

    private init() {
        // Setup date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Create logs directory
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DropBeat")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Create log file
        logFileURL = logsDir.appendingPathComponent("app.log")

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        // Open file handle for writing
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()

        // Log startup
        log("📱 DropBeat Started", category: .app)
        log("📝 Log file: \(logFileURL.path)", category: .app)
    }

    enum LogCategory: String {
        case app = "APP"
        case backend = "BACKEND"
        case player = "PLAYER"
        case network = "NETWORK"
        case error = "ERROR"
        case warning = "WARNING"
        case info = "INFO"
    }

    /// Log a message to both console and file
    func log(_ message: String, category: LogCategory = .info) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let timestamp = self.dateFormatter.string(from: Date())
            let logLine = "[\(timestamp)] [\(category.rawValue)] \(message)\n"

            // Write to console
            print(logLine.trimmingCharacters(in: .newlines))

            // Write to file
            if let data = logLine.data(using: .utf8) {
                self.fileHandle?.write(data)
            }
        }
    }

    /// Get the path to the log file
    func getLogFilePath() -> String {
        return logFileURL.path
    }

    /// Open the log file in Console.app
    func openLogFile() {
        NSWorkspace.shared.open(logFileURL)
    }

    /// Get recent log lines (last N lines)
    func getRecentLogs(lines: Int = 100) -> String {
        guard let logContent = try? String(contentsOf: logFileURL) else {
            return "Unable to read log file"
        }

        let allLines = logContent.components(separatedBy: .newlines)
        let recentLines = allLines.suffix(lines)
        return recentLines.joined(separator: "\n")
    }

    /// Clear the log file
    func clearLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.fileHandle?.truncateFile(atOffset: 0)
            self.log("🗑️ Logs cleared", category: .app)
        }
    }

    deinit {
        log("📱 DropBeat Stopped", category: .app)
        try? fileHandle?.close()
    }
}

// Convenience methods
extension AppLogger {
    func info(_ message: String) {
        log(message, category: .info)
    }

    func warning(_ message: String) {
        log("⚠️ \(message)", category: .warning)
    }

    func error(_ message: String) {
        log("❌ \(message)", category: .error)
    }

    func backend(_ message: String) {
        log(message, category: .backend)
    }

    func player(_ message: String) {
        log(message, category: .player)
    }

    func network(_ message: String) {
        log(message, category: .network)
    }
}
