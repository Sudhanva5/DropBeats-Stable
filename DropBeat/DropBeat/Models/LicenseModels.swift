import Foundation

public struct License: Codable {
    public let id: String
    public let name: String
    public let email: String
    public let country: String?
    public let licenseKey: String
    public let deviceId: String?
    public let isActive: Bool
    public let createdAt: Date
    public let hasCompletedOnboarding: Bool
    
    public init(id: String, name: String, email: String, country: String?, licenseKey: String, deviceId: String?, isActive: Bool, createdAt: Date, hasCompletedOnboarding: Bool) {
        self.id = id
        self.name = name
        self.email = email
        self.country = country
        self.licenseKey = licenseKey
        self.deviceId = deviceId
        self.isActive = isActive
        self.createdAt = createdAt
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case country
        case licenseKey = "license_key"
        case deviceId = "device_id"
        case isActive = "is_active"
        case createdAt = "created_at"
        case hasCompletedOnboarding = "has_completed_onboarding"
    }
}

public struct LicenseValidationResponse: Codable {
    public let valid: Bool
    public let error: String?
    public let name: String?
    public let email: String?
    public let country: String?
    public let createdAt: Date?
    public let hasCompletedOnboarding: Bool?
    
    enum CodingKeys: String, CodingKey {
        case valid
        case error
        case name
        case email
        case country
        case createdAt = "created_at"
        case hasCompletedOnboarding = "has_completed_onboarding"
    }
}

public struct LicenseDeactivationResponse: Codable {
    public let success: Bool
    public let message: String
    public let error: String?
} 