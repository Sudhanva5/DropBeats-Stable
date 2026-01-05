import Foundation

/// Manages the local Python backend server lifecycle
class BackendServerManager {
    static let shared = BackendServerManager()

    private var serverProcess: Process?
    private let serverPort = 4002
    private var isStarting = false

    private init() {}

    // MARK: - Server Status

    /// Check if the backend server is running and healthy
    func isServerRunning(completion: @escaping (Bool) -> Void) {
        let url = URL(string: "http://localhost:\(serverPort)/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                print("✅ [BackendServer] Server is healthy on port \(self.serverPort)")
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
    }

    /// Synchronous version for quick checks
    func isServerRunningSync() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        isServerRunning { isRunning in
            result = isRunning
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 3.0)
        return result
    }

    // MARK: - Server Lifecycle

    /// Start the Python backend server automatically
    func startServer(completion: @escaping (Bool) -> Void) {
        // Prevent concurrent starts
        guard !isStarting else {
            print("⏳ [BackendServer] Server start already in progress")
            completion(false)
            return
        }

        // Check if already running
        isServerRunning { [weak self] isRunning in
            guard let self = self else { return }

            if isRunning {
                print("🟢 [BackendServer] Server already running on port \(self.serverPort)")
                completion(true)
                return
            }

            self.isStarting = true
            self.launchServerProcess(completion: completion)
        }
    }

    private func launchServerProcess(completion: @escaping (Bool) -> Void) {
        // Get path to bundled backend or use development path
        let backendPath = getBackendPath()

        guard FileManager.default.fileExists(atPath: backendPath) else {
            print("❌ [BackendServer] Backend files not found at: \(backendPath)")
            self.isStarting = false
            completion(false)
            return
        }

        print("🚀 [BackendServer] Starting server from: \(backendPath)")

        // Find python3 executable (handle different installation locations)
        guard let python3Path = findPython3Executable() else {
            print("❌ [BackendServer] python3 not found. Please install Python 3")
            self.isStarting = false
            completion(false)
            return
        }

        print("🐍 [BackendServer] Using Python at: \(python3Path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python3Path)
        process.arguments = [
            "-m", "uvicorn",
            "main:app",
            "--host", "127.0.0.1",
            "--port", "\(serverPort)",
            "--log-level", "info"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: backendPath)

        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Monitor server output
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("📋 [BackendServer] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("⚠️ [BackendServer] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        do {
            try process.run()
            self.serverProcess = process
            print("✅ [BackendServer] Server process launched (PID: \(process.processIdentifier))")

            // Wait for server to be ready
            self.waitForServerReady(attempts: 15, completion: completion)
        } catch {
            print("❌ [BackendServer] Failed to start server: \(error)")
            self.isStarting = false
            completion(false)
        }
    }

    private func waitForServerReady(attempts: Int, completion: @escaping (Bool) -> Void) {
        guard attempts > 0 else {
            print("❌ [BackendServer] Server failed to become ready after 15 seconds")
            self.isStarting = false
            completion(false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            self.isServerRunning { isRunning in
                if isRunning {
                    print("🎉 [BackendServer] Server is ready!")
                    self.isStarting = false
                    completion(true)
                } else {
                    print("⏳ [BackendServer] Waiting for server... (\(attempts) attempts left)")
                    self.waitForServerReady(attempts: attempts - 1, completion: completion)
                }
            }
        }
    }

    /// Stop the backend server
    func stopServer() {
        guard let process = serverProcess, process.isRunning else {
            print("⚠️ [BackendServer] No server process to stop")
            return
        }

        print("🛑 [BackendServer] Stopping server (PID: \(process.processIdentifier))")
        process.terminate()

        // Wait for graceful shutdown
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if let process = self?.serverProcess, process.isRunning {
                print("⚠️ [BackendServer] Force killing server process")
                process.interrupt()
            }
        }

        serverProcess = nil
    }

    // MARK: - Python Resolution

    /// Find python3 executable in common locations
    private func findPython3Executable() -> String? {
        let commonPaths = [
            "/usr/bin/python3",              // System Python (macOS default)
            "/usr/local/bin/python3",        // Homebrew (Intel)
            "/opt/homebrew/bin/python3",     // Homebrew (Apple Silicon)
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",  // Official Python.org installer
            "/opt/local/bin/python3",        // MacPorts
            "~/.pyenv/shims/python3"         // pyenv
        ]

        // Try bundled Python first (for production distribution)
        if let bundledPython = getBundledPythonPath() {
            if FileManager.default.isExecutableFile(atPath: bundledPython) {
                print("🐍 [BackendServer] Found bundled Python at: \(bundledPython)")
                return bundledPython
            }
        }

        // Try common system paths
        for path in commonPaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expandedPath) {
                print("🐍 [BackendServer] Found Python at: \(expandedPath)")
                return expandedPath
            }
        }

        // Try using 'which python3' command
        if let whichPath = runWhichCommand("python3") {
            print("🐍 [BackendServer] Found Python via 'which': \(whichPath)")
            return whichPath
        }

        print("❌ [BackendServer] Python 3 not found in common locations")
        return nil
    }

    /// Get path to bundled Python (if included in app bundle)
    private func getBundledPythonPath() -> String? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }

        // Check for bundled Python in Resources
        let bundledPaths = [
            "\(resourcePath)/python/bin/python3",
            "\(resourcePath)/Python.framework/Versions/Current/bin/python3"
        ]

        for path in bundledPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Run 'which' command to find executable
    private func runWhichCommand(_ executable: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executable]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    return output
                }
            }
        } catch {
            print("⚠️ [BackendServer] Failed to run 'which': \(error)")
        }

        return nil
    }

    // MARK: - Path Resolution

    private func getBackendPath() -> String {
        // Try bundled path first (production)
        if let bundledPath = Bundle.main.resourcePath?.appending("/backend/api") {
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }

        // Fall back to development path
        let workspaceRoot = "/Users/sudhanvaacharya/Desktop/Code Projects/DropBeat-Stable-New"
        let devPath = "\(workspaceRoot)/Server/api"

        if FileManager.default.fileExists(atPath: devPath) {
            print("🔧 [BackendServer] Using development backend path")
            return devPath
        }

        // Last resort: check relative to executable
        if let executablePath = Bundle.main.executablePath {
            let execDir = (executablePath as NSString).deletingLastPathComponent
            let relativePath = "\(execDir)/../Resources/backend/api"
            if FileManager.default.fileExists(atPath: relativePath) {
                return relativePath
            }
        }

        return devPath // Return dev path even if not found (will fail later with clear error)
    }

    // MARK: - Cleanup

    deinit {
        stopServer()
    }
}
