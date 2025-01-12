import Foundation
import SwiftUI

class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    @Published var licenseStatus: LicenseStatus = .unknown
    @Published var licenseInfo: LicenseInfo?
    
    private init() {}
    
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
        
        static func == (lhs: LicenseInfo, rhs: LicenseInfo) -> Bool {
            return lhs.name == rhs.name &&
                   lhs.email == rhs.email &&
                   lhs.country == rhs.country &&
                   lhs.createdAt == rhs.createdAt
        }
    }
    
    func validateLicenseOnStartup() async {
        // Get the saved license key from UserDefaults
        guard let licenseKey = UserDefaults.standard.string(forKey: "licenseKey") else {
            DispatchQueue.main.async {
                self.licenseStatus = .invalid("No license key found")
            }
            return
        }
        
        do {
            let response = try await LicenseService.shared.validateLicense(key: licenseKey)
            
            DispatchQueue.main.async {
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
                            createdAt: createdAt
                        )
                    }
                } else {
                    self.licenseStatus = .invalid(response.error ?? "Invalid license")
                }
            }
        } catch {
            DispatchQueue.main.async {
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
} 