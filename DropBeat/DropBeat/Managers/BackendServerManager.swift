import Foundation

/// Manages the local Python backend server lifecycle with auto-restart
class BackendServerManager {
    static let shared = BackendServerManager()

    private var serverProcess: Process?
    private let serverPort = 4002
    private var isStarting = false
    private var monitorTimer: Timer?
    private var restartAttempts = 0
    private let maxRestartAttempts = 5
    private var lastRestartTime: Date?

    private let logger = AppLogger.shared

    private init() {
        logger.backend("🔧 BackendServerManager initialized")
    }

    // MARK: - Server Status

    /// Check if the backend server is running and healthy
    func isServerRunning(completion: @escaping (Bool) -> Void) {
        let url = URL(string: "http://localhost:\(serverPort)/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                self?.logger.backend("✅ Server is healthy on port \(self?.serverPort ?? 0)")
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

    /// Start the Python backend server with auto-restart monitoring
    func startServer(completion: @escaping (Bool) -> Void) {
        // Prevent concurrent starts
        guard !isStarting else {
            logger.backend("⏳ Server start already in progress")
            completion(false)
            return
        }

        logger.backend("🚀 Starting backend server...")

        // Check if already running
        isServerRunning { [weak self] isRunning in
            guard let self = self else { return }

            if isRunning {
                self.logger.backend("🟢 Server already running on port \(self.serverPort)")
                self.startMonitoring()
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
        logger.backend("📂 Backend path: \(backendPath)")

        guard FileManager.default.fileExists(atPath: backendPath) else {
            logger.error("Backend files not found at: \(backendPath)")
            self.isStarting = false
            completion(false)
            return
        }

        // Find python3 executable (handle different installation locations)
        guard let python3Path = findPython3Executable() else {
            logger.error("python3 not found. Please install Python 3")
            self.isStarting = false
            completion(false)
            return
        }

        logger.backend("🐍 Using Python at: \(python3Path)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python3Path)
        process.arguments = [
            // -B stops Python from writing __pycache__ into the app bundle.
            // Without it the server writes bytecode next to the modules it
            // imports, which are inside Contents/Resources, and that breaks the
            // code signature seal on the user's installed copy.
            "-B",
            "-m", "uvicorn",
            "main:app",
            "--host", "127.0.0.1",
            "--port", "\(serverPort)",
            "--log-level", "info"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: backendPath)

        // -B above only covers uvicorn itself. The backend shells out to
        // yt-dlp as a child process, and that child re-imports half the
        // stdlib, writing __pycache__ all over Contents/Resources - which
        // breaks the code signature seal ("a sealed resource is missing or
        // invalid") on the user's installed copy. The env var is inherited by
        // every descendant, so it covers subprocesses we add later too.
        var env = ProcessInfo.processInfo.environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = env

        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Monitor server output
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.logger.backend("📋 \(trimmed)")
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.logger.backend("⚠️ \(trimmed)")
            }
        }

        // Monitor process termination
        process.terminationHandler = { [weak self] process in
            guard let self = self else { return }

            let exitCode = process.terminationStatus
            self.logger.backend("💀 Server process terminated with exit code: \(exitCode)")

            // Auto-restart if not intentionally stopped
            if self.serverProcess != nil {
                self.handleServerCrash()
            }
        }

        do {
            try process.run()
            self.serverProcess = process
            logger.backend("✅ Server process launched (PID: \(process.processIdentifier))")

            // Wait for server to be ready
            self.waitForServerReady(attempts: 15, completion: { [weak self] success in
                if success {
                    self?.startMonitoring()
                    self?.restartAttempts = 0 // Reset on successful start
                }
                completion(success)
            })
        } catch {
            logger.error("Failed to start server: \(error.localizedDescription)")
            self.isStarting = false
            completion(false)
        }
    }

    private func waitForServerReady(attempts: Int, completion: @escaping (Bool) -> Void) {
        guard attempts > 0 else {
            logger.error("Server failed to become ready after 15 seconds")
            self.isStarting = false
            completion(false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            self.isServerRunning { isRunning in
                if isRunning {
                    self.logger.backend("🎉 Server is ready and responding!")
                    self.isStarting = false
                    completion(true)
                } else {
                    self.logger.backend("⏳ Waiting for server... (\(attempts) attempts left)")
                    self.waitForServerReady(attempts: attempts - 1, completion: completion)
                }
            }
        }
    }

    // MARK: - Auto-Restart Logic

    private func startMonitoring() {
        logger.backend("👁️ Starting server health monitoring (checks every 30s)")

        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkServerHealth()
        }
    }

    private func checkServerHealth() {
        isServerRunning { [weak self] isRunning in
            guard let self = self else { return }

            if !isRunning && self.serverProcess != nil {
                self.logger.warning("Server health check failed - server is down")
                self.handleServerCrash()
            }
        }
    }

    private func handleServerCrash() {
        logger.warning("🔄 Attempting to auto-restart server...")

        // Check if we should attempt restart
        let now = Date()
        if let lastRestart = lastRestartTime,
           now.timeIntervalSince(lastRestart) < 60 {
            restartAttempts += 1
        } else {
            // Reset attempts if last restart was more than 1 minute ago
            restartAttempts = 1
        }
        lastRestartTime = now

        if restartAttempts > maxRestartAttempts {
            logger.error("❌ Max restart attempts (\(maxRestartAttempts)) reached. Server will not auto-restart.")
            logger.error("Please restart the DropBeat app manually")
            serverProcess = nil
            return
        }

        logger.backend("🔄 Auto-restart attempt \(restartAttempts)/\(maxRestartAttempts)")

        // Clean up dead process
        serverProcess = nil
        isStarting = false

        // Wait a bit before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startServer { success in
                if success {
                    self?.logger.backend("✅ Server auto-restarted successfully")
                } else {
                    self?.logger.error("❌ Server auto-restart failed")
                }
            }
        }
    }

    /// Stop the backend server
    func stopServer() {
        monitorTimer?.invalidate()
        monitorTimer = nil

        guard let process = serverProcess, process.isRunning else {
            logger.backend("⚠️ No server process to stop")
            return
        }

        logger.backend("🛑 Stopping server (PID: \(process.processIdentifier))")
        process.terminate()

        // Wait for graceful shutdown
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if let process = self?.serverProcess, process.isRunning {
                self?.logger.warning("Force killing server process")
                process.interrupt()
            }
        }

        serverProcess = nil
    }

    // MARK: - Python Resolution

    /// Find python3 executable in common locations
    private func findPython3Executable() -> String? {
        logger.backend("🔍 Searching for Python executable...")

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
                logger.backend("✅ Found bundled Python at: \(bundledPython)")
                return bundledPython
            } else {
                logger.backend("⚠️ Bundled Python found but not executable: \(bundledPython)")
            }
        }

        // Try common system paths
        for path in commonPaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expandedPath) {
                logger.backend("✅ Found Python at: \(expandedPath)")
                return expandedPath
            }
        }

        // Try using 'which python3' command
        if let whichPath = runWhichCommand("python3") {
            logger.backend("✅ Found Python via 'which': \(whichPath)")
            return whichPath
        }

        logger.error("❌ Python 3 not found in any common locations")
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
                logger.backend("📦 Found bundled Python candidate: \(path)")
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
            logger.warning("Failed to run 'which': \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - Path Resolution

    private func getBackendPath() -> String {
        // Try bundled path first (production)
        if let bundledPath = Bundle.main.resourcePath?.appending("/backend/api") {
            if FileManager.default.fileExists(atPath: bundledPath) {
                logger.backend("📦 Using bundled backend path")
                return bundledPath
            }
        }

        // Fall back to development path
        let workspaceRoot = "/Users/sudhanvaacharya/Desktop/Code Projects/DropBeat-Stable-New"
        let devPath = "\(workspaceRoot)/Server/api"

        if FileManager.default.fileExists(atPath: devPath) {
            logger.backend("🔧 Using development backend path")
            return devPath
        }

        // Last resort: check relative to executable
        if let executablePath = Bundle.main.executablePath {
            let execDir = (executablePath as NSString).deletingLastPathComponent
            let relativePath = "\(execDir)/../Resources/backend/api"
            if FileManager.default.fileExists(atPath: relativePath) {
                logger.backend("📂 Using relative backend path")
                return relativePath
            }
        }

        return devPath // Return dev path even if not found (will fail later with clear error)
    }

    // MARK: - Cleanup

    deinit {
        monitorTimer?.invalidate()
        stopServer()
    }
}
