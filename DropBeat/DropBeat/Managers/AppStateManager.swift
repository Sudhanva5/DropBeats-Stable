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
    
    private init() {
        // Load onboarding state from UserDefaults
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        lastValidationTime = UserDefaults.standard.object(forKey: "lastLicenseValidation") as? Date
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
        // Get the saved license key from UserDefaults
        guard let licenseKey = UserDefaults.standard.string(forKey: "licenseKey") else {
            await MainActor.run {
                self.licenseStatus = .invalid("No license key found")
                self.forceOnboarding()
            }
            return
        }
        
        do {
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
                            hasCompletedOnboarding: response.hasCompletedOnboarding ?? false
                        )
                        
                        // Update onboarding state
                        self.hasCompletedOnboarding = response.hasCompletedOnboarding ?? false
                        UserDefaults.standard.set(self.hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
                    }
                    
                    // Update last validation time
                    self.lastValidationTime = Date()
                    UserDefaults.standard.set(self.lastValidationTime, forKey: "lastLicenseValidation")
                } else {
                    self.licenseStatus = .invalid(response.error ?? "Invalid license")
                    self.forceOnboarding()
                }
            }
        } catch {
            await MainActor.run {
                self.licenseStatus = .invalid(error.localizedDescription)
                self.forceOnboarding()
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