import Foundation
import Supabase
import IOKit

final class LicenseService {
    static let shared = LicenseService()
    private let supabase: SupabaseClient
    
    private init() {
        guard let supabaseURL = URL(string: SupabaseConfig.projectURL) else {
            fatalError("Invalid Supabase URL")
        }
        
        self.supabase = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: SupabaseConfig.anonKey
        )
    }
    
    func validateLicense(key: String) async throws -> LicenseValidationResponse {
        print("Starting license validation for key: \(key)")
        
        let response = try await supabase.database
            .rpc(
                "validate_license",
                params: [
                    "p_license_key": key,
                    "p_device_id": nil
                ]
            )
            .execute()
            .data
        
        // Debug: Print raw response
        if let jsonString = String(data: response, encoding: .utf8) {
            print("Raw Response: \(jsonString)")
        }
        
        let decoder = JSONDecoder()
        
        // Support multiple date formats
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            // Try ISO8601 first
            if let date = ISO8601DateFormatter().date(from: dateString) {
                return date
            }
            
            // Try other formats
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd HH:mm:ss"
            ]
            
            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateString)"
            )
        }
        
        do {
            return try decoder.decode(LicenseValidationResponse.self, from: response)
        } catch {
            print("Decoding Error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, _):
                    print("Missing key: \(key)")
                case .typeMismatch(let type, _):
                    print("Type mismatch: \(type)")
                case .valueNotFound(let type, _):
                    print("Value not found: \(type)")
                default:
                    print("Other decoding error: \(decodingError)")
                }
            }
            throw error
        }
    }
    
    func deactivateLicense(key: String, email: String) async throws -> LicenseDeactivationResponse {
        let response = try await supabase.database
            .rpc(
                "deactivate_license",
                params: [
                    "p_license_key": key,
                    "p_email": email
                ]
            )
            .execute()
            .data
        
        // Debug: Print raw response
        if let jsonString = String(data: response, encoding: .utf8) {
            print("Raw Response: \(jsonString)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(LicenseDeactivationResponse.self, from: response)
    }
    
    // Test function to validate the license functionality
    func testLicenseValidation(key: String) async {
        do {
            let response = try await validateLicense(key: key)
            print("License Validation Response:")
            print("Valid: \(response.valid)")
            
            if response.valid {
                print("\nLicense Details:")
                if let email = response.email {
                    print("- Email: \(email)")
                }
                if let createdAt = response.createdAt {
                    print("- Created: \(createdAt)")
                }
            }
            
            if let error = response.error {
                print("Error: \(error)")
            }
        } catch {
            print("Error validating license: \(error.localizedDescription)")
        }
    }
    
    func getDeviceIdentifier() async throws -> String {
        // Get system UUID as device identifier
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard platformExpert > 0 else {
            throw LicenseError.deviceIdGenerationFailed
        }
        defer { IOObjectRelease(platformExpert) }
        
        guard let serialNumber = IORegistryEntryCreateCFProperty(platformExpert, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeUnretainedValue() as? String else {
            throw LicenseError.deviceIdGenerationFailed
        }
        
        return serialNumber
    }
    
    func updateOnboardingStatus(key: String, completed: Bool) async throws {
        print("Updating onboarding status for key: \(key)")
        
        let response = try await supabase.database
            .rpc(
                "update_onboarding_status",
                params: [
                    "p_license_key": key,
                    "p_has_completed": String(completed)
                ]
            )
            .execute()
            .data
            
        // Debug: Print raw response
        if let jsonString = String(data: response, encoding: .utf8) {
            print("Raw Response: \(jsonString)")
        }
    }
}

// Parameter types for Supabase functions
struct ValidateLicenseParams: Codable {
    let licenseKey: String
    let deviceId: String
    
    enum CodingKeys: String, CodingKey {
        case licenseKey = "p_license_key"
        case deviceId = "p_device_id"
    }
}

struct DeactivateLicenseParams: Codable {
    let licenseKey: String
    let email: String
    
    enum CodingKeys: String, CodingKey {
        case licenseKey = "p_license_key"
        case email = "p_email"
    }
}

enum LicenseError: LocalizedError {
    case deviceIdGenerationFailed
    case invalidLicenseKey
    case licenseAlreadyActivated
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .deviceIdGenerationFailed:
            return "Failed to generate device identifier"
        case .invalidLicenseKey:
            return "Invalid license key"
        case .licenseAlreadyActivated:
            return "License is already activated on another device"
        case .networkError:
            return "Network error occurred"
        }
    }
} 
