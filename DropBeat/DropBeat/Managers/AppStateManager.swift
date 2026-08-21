import Foundation
import SwiftUI

enum LicenseStatus: Equatable {
    case valid
    case invalid(String)
    case unknown
}

class AppStateManager: ObservableObject {
    static let shared: AppStateManager = {
        let instance = AppStateManager()
        return instance
    }()
    
    @Published private(set) var licenseStatus: LicenseStatus = .unknown {
        didSet {
            if oldValue != licenseStatus {
                NotificationCenter.default.post(
                    name: NSNotification.Name("LicenseStatusChanged"),
                    object: nil
                )
            }
        }
    }
    @Published private(set) var licenseInfo: LicenseInfo?
    @Published private(set) var hasCompletedOnboarding: Bool = false {
        didSet {
            if oldValue != hasCompletedOnboarding {
                // Post notification when onboarding state changes
                NotificationCenter.default.post(
                    name: NSNotification.Name("OnboardingStateChanged"),
                    object: nil,
                    userInfo: ["completed": hasCompletedOnboarding]
                )
            }
        }
    }
    
    private let validationInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    private var lastValidationTime: Date?

    // Prevent aggressive re-validation
    private var isValidationInProgress = false
    private var lastValidationAttemptTime: Date?
    private let minValidationInterval: TimeInterval = 10 // Don't validate more than once per 10 seconds

    /// How long a licence stays trusted while the backend cannot be reached.
    ///
    /// Everything between a user and their licence is now remote — Cloudflare,
    /// Railway, Postgres — plus whatever their ISP is doing. Without a grace
    /// window, any one of those failing locks a paying customer out of an app
    /// they already bought, which is a far worse outcome than briefly trusting
    /// a licence that was valid a fortnight ago.
    private let offlineGracePeriod: TimeInterval = 14 * 24 * 60 * 60

    private init() {
        // Load onboarding state from UserDefaults
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        lastValidationTime = UserDefaults.standard.object(forKey: "lastLicenseValidation") as? Date

        restoreCachedLicenseState()
    }

    /// Restore the last known-good licence before the first network call.
    ///
    /// Without this, `licenseStatus` starts `.unknown` and `licenseInfo` starts
    /// nil on every launch, so the network-error branch in
    /// validateLicenseOnStartup — which is written to keep a valid licence
    /// valid — is unreachable on a cold start, and the app falls through to
    /// `.invalid`. The effect was that any backend outage locked out every
    /// paying user the next time they restarted the app.
    private func restoreCachedLicenseState() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "licenseKey") != nil,
              let cachedAt = defaults.object(forKey: "lastSuccessfulValidation") as? Date,
              let name = defaults.string(forKey: "cachedLicenseName"),
              let email = defaults.string(forKey: "cachedLicenseEmail"),
              let country = defaults.string(forKey: "cachedLicenseCountry"),
              let createdAt = defaults.object(forKey: "cachedLicenseCreatedAt") as? Date
        else { return }

        guard Date().timeIntervalSince(cachedAt) < offlineGracePeriod else {
            print("🔐 [DropBeat] Cached licence is older than the grace period; a live check is required")
            return
        }

        licenseInfo = LicenseInfo(
            name: name,
            email: email,
            country: country,
            createdAt: createdAt,
            hasCompletedOnboarding: defaults.bool(forKey: "hasCompletedOnboarding")
        )
        licenseStatus = .valid
        print("🔐 [DropBeat] Restored cached licence from \(cachedAt); revalidating in the background")
    }

    /// Persist the last known-good licence so the next cold start can trust it.
    /// Only ever called after the server has explicitly said the licence is valid.
    private func cacheLicenseState(_ info: LicenseInfo, at date: Date) {
        let defaults = UserDefaults.standard
        defaults.set(date, forKey: "lastSuccessfulValidation")
        defaults.set(info.name, forKey: "cachedLicenseName")
        defaults.set(info.email, forKey: "cachedLicenseEmail")
        defaults.set(info.country, forKey: "cachedLicenseCountry")
        defaults.set(info.createdAt, forKey: "cachedLicenseCreatedAt")
    }

    /// Drop the cache. Used when the server explicitly rejects a licence, so a
    /// revoked or refunded licence cannot survive on disk for a fortnight.
    private func clearCachedLicenseState() {
        let defaults = UserDefaults.standard
        for key in ["lastSuccessfulValidation", "cachedLicenseName",
                    "cachedLicenseEmail", "cachedLicenseCountry",
                    "cachedLicenseCreatedAt"] {
            defaults.removeObject(forKey: key)
        }
    }
    
    func initialize() {
        // Setup periodic validation
        setupPeriodicValidation()
        
        // Setup wake from sleep observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Load initial state
        Task {
            await validateLicenseOnStartup()
        }
    }
    
    @objc private func handleWakeFromSleep() {
        Task {
            await validateLicenseOnStartup()
        }
    }
    
    private func setupPeriodicValidation() {
        Task {
            while true {
                // Check if it's time to validate
                if let lastTime = lastValidationTime {
                    let timeSinceLastValidation = Date().timeIntervalSince(lastTime)
                    if timeSinceLastValidation >= validationInterval {
                        await validateLicenseOnStartup()
                    }
                }
                
                // Sleep for 1 hour (3600 seconds)
                try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000)
            }
        }
    }
    
    func validateLicenseOnStartup() async {
        // Prevent aggressive re-validation within the minimum interval
        let now = Date()
        if let lastAttempt = lastValidationAttemptTime {
            let timeSinceLastAttempt = now.timeIntervalSince(lastAttempt)
            if timeSinceLastAttempt < minValidationInterval {
                print("⏳ [DropBeat] License validation already in progress or recently attempted, skipping")
                return
            }
        }

        // Prevent multiple simultaneous validation attempts
        if isValidationInProgress {
            print("🔄 [DropBeat] License validation already in progress, skipping duplicate request")
            return
        }

        // Get the saved license key from UserDefaults
        guard let licenseKey = UserDefaults.standard.string(forKey: "licenseKey") else {
            await MainActor.run {
                self.licenseStatus = .invalid("No license key found")
                self.forceOnboarding()
            }
            return
        }

        await MainActor.run {
            self.isValidationInProgress = true
            self.lastValidationAttemptTime = now
        }

        // Retry logic with exponential backoff
        var retryCount = 0
        let maxRetries = 2
        var lastError: Error?

        while retryCount < maxRetries {
            do {
                let response = try await LicenseService.shared.validateLicense(key: licenseKey)

                await MainActor.run {
                    self.isValidationInProgress = false

                    if response.valid {
                        print("✅ [DropBeat] License validation successful")
                        self.licenseStatus = .valid
                        if let email = response.email,
                           let name = response.name,
                           let country = response.country,
                           let createdAt = response.createdAt {
                            let info = LicenseInfo(
                                name: name,
                                email: email,
                                country: country,
                                createdAt: createdAt,
                                hasCompletedOnboarding: response.hasCompletedOnboarding ?? false
                            )
                            self.licenseInfo = info

                            // Update onboarding state
                            self.hasCompletedOnboarding = response.hasCompletedOnboarding ?? false
                            UserDefaults.standard.set(self.hasCompletedOnboarding, forKey: "hasCompletedOnboarding")

                            // Remember this good answer so a later outage does
                            // not lock the user out on their next cold start.
                            self.cacheLicenseState(info, at: now)
                        }

                        // Update last validation time
                        self.lastValidationTime = now
                        UserDefaults.standard.set(self.lastValidationTime, forKey: "lastLicenseValidation")
                    } else {
                        // Server explicitly says the license is invalid - this is a permanent state.
                        // Clear the offline cache too: a revoked or refunded licence must not
                        // keep working for the remainder of the grace window.
                        print("❌ [DropBeat] Server returned invalid license: \(response.error ?? "unknown error")")
                        self.clearCachedLicenseState()
                        self.licenseStatus = .invalid(response.error ?? "Invalid license")
                        self.forceOnboarding()
                    }
                }
                return
            } catch {
                lastError = error
                retryCount += 1

                if retryCount < maxRetries {
                    // Exponential backoff: 1 second, then 2 seconds
                    let delay = TimeInterval(pow(2.0, Double(retryCount - 1)))
                    print("⚠️ [DropBeat] License validation failed (attempt \(retryCount)/\(maxRetries)), retrying in \(delay)s: \(error)")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    print("❌ [DropBeat] License validation failed after \(maxRetries) attempts: \(error)")
                }
            }
        }

        // All retries exhausted - handle network error gracefully
        await MainActor.run {
            self.isValidationInProgress = false

            // CRITICAL FIX: Don't invalidate on network errors - only on explicit server rejection
            // If we have a valid license cached and it's a network error, keep the existing state
            if licenseKey == UserDefaults.standard.string(forKey: "licenseKey"),
               let licenseInfo = self.licenseInfo,
               case .valid = self.licenseStatus {
                // Network error but we have a valid cached license - keep it valid
                print("🔐 [DropBeat] Network error validating license, but keeping cached valid license")
                // Update the timestamp anyway since we tried to validate
                self.lastValidationTime = now
                UserDefaults.standard.set(self.lastValidationTime, forKey: "lastLicenseValidation")
            } else if self.licenseStatus == .unknown {
                // Only mark as invalid if we've never successfully validated before
                print("⚠️ [DropBeat] License validation failed and no cached license found: \(lastError?.localizedDescription ?? "unknown error")")
                self.licenseStatus = .invalid("Unable to validate license - check your internet connection")
                // Don't force onboarding here - give user a chance to retry
            }
        }
    }
    
    private func forceOnboarding() {
        // Clear existing license data
        UserDefaults.standard.removeObject(forKey: "licenseKey")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        hasCompletedOnboarding = false
        licenseInfo = nil
        
        // Post notification to show onboarding
        NotificationCenter.default.post(name: NSNotification.Name("ShowOnboarding"), object: nil)
    }
    
    struct LicenseInfo: Equatable {
        let name: String
        let email: String
        let country: String
        let createdAt: Date
        let hasCompletedOnboarding: Bool
        
        static func == (lhs: LicenseInfo, rhs: LicenseInfo) -> Bool {
            return lhs.name == rhs.name &&
                   lhs.email == rhs.email &&
                   lhs.country == rhs.country &&
                   lhs.createdAt == rhs.createdAt &&
                   lhs.hasCompletedOnboarding == rhs.hasCompletedOnboarding
        }
        
        static let defaultCountry = "India"
    }
    
    func saveLicenseKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "licenseKey")
    }
    
    func getLicenseKey() -> String? {
        return UserDefaults.standard.string(forKey: "licenseKey")
    }
    
    func setOnboardingCompleted() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        
        // Update onboarding status in database and validate license
        Task {
            guard let licenseKey = getLicenseKey() else { return }
            do {
                // Update onboarding status
                try await LicenseService.shared.updateOnboardingStatus(key: licenseKey, completed: true)
                
                // Validate license to update app state
                let response = try await LicenseService.shared.validateLicense(key: licenseKey)
                await MainActor.run {
                    if response.valid {
                        self.licenseStatus = .valid
                        if let email = response.email,
                           let name = response.name,
                           let country = response.country,
                           let createdAt = response.createdAt {
                            self.licenseInfo = LicenseInfo(
                                name: name,
                                email: email,
                                country: country,
                                createdAt: createdAt,
                                hasCompletedOnboarding: true
                            )
                        }
                    } else {
                        self.licenseStatus = .invalid(response.error ?? "Invalid license key")
                    }
                }
            } catch {
                print("Failed to update onboarding status in database:", error)
                await MainActor.run {
                    self.licenseStatus = .invalid("Failed to validate license: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func validateLicense() async {
        // Get the saved license key
        guard let licenseKey = UserDefaults.standard.string(forKey: "licenseKey") else {
            DispatchQueue.main.async { [weak self] in
                self?.licenseStatus = .invalid("No license key found")
            }
            return
        }
        
        do {
            let response = try await LicenseService.shared.validateLicense(key: licenseKey)
            DispatchQueue.main.async { [weak self] in
                self?.licenseStatus = response.valid ? .valid : .invalid("Invalid license key")
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.licenseStatus = .invalid("License validation failed: \(error.localizedDescription)")
            }
        }
    }
    
    func startPeriodicValidation() {
        Task {
            while true {
                // Sleep for 1 hour (3600 seconds)
                try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000)
                await validateLicense()
            }
        }
    }
} 