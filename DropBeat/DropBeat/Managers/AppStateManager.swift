import Foundation
import SwiftUI

class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    @Published var licenseStatus: LicenseStatus = .unknown
    @Published var licenseInfo: LicenseInfo?
    @Published var hasCompletedOnboarding: Bool = false
    
    private init() {
        // Load onboarding state from UserDefaults
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }
    
    enum LicenseStatus: Equatable {
        case unknown
        case valid
        case invalid(String)
        
        static func == (lhs: LicenseStatus, rhs: LicenseStatus) -> Bool {
            switch (lhs, rhs) {
            case (.unknown, .unknown):
                return true
            case (.valid, .valid):
                return true
            case (.invalid(let lhsError), .invalid(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
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
    
    func validateLicenseOnStartup() async {
        // Get the saved license key from UserDefaults
        guard let licenseKey = UserDefaults.standard.string(forKey: "licenseKey") else {
            await MainActor.run {
                self.licenseStatus = .invalid("No license key found")
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
                } else {
                    self.licenseStatus = .invalid(response.error ?? "Invalid license")
                }
            }
        } catch {
            await MainActor.run {
                self.licenseStatus = .invalid(error.localizedDescription)
            }
        }
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
    }
} 