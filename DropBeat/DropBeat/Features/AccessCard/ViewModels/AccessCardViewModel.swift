import SwiftUI

class AccessCardViewModel: ObservableObject {
    @Published var primaryColor: Color
    @Published var gradientColors: [Color]
    
    // User info
    @Published var userName: String = "Unknown User"
    @Published var userEmail: String = ""
    
    // License info
    @Published var licensePrefix: String = "DB"
    @Published var licenseYear: String = String(Calendar.current.component(.year, from: Date()))
    @Published var licenseCode: String = "----"
    @Published var licenseValidity: String = "Inactive"
    @Published var memberSince: String = ""
    
    // MARK: - Gradient Presets
    private static let gradientPresets: [[Color]] = [
        // Deep Coral Sunset
        [
            Color(red: 0.95, green: 0.30, blue: 0.25),   // Deep Coral
            Color(red: 0.90, green: 0.35, blue: 0.20),   // Rich Orange
            Color(red: 0.85, green: 0.25, blue: 0.30),   // Deep Rose
            Color(red: 0.95, green: 0.30, blue: 0.25)    // Deep Coral
        ],
        // Royal Sapphire
        [
            Color(red: 0.15, green: 0.25, blue: 0.95),   // Deep Royal Blue
            Color(red: 0.20, green: 0.30, blue: 1.0),    // Rich Sapphire
            Color(red: 0.10, green: 0.20, blue: 0.90),   // Deep Blue
            Color(red: 0.15, green: 0.25, blue: 0.95)    // Deep Royal Blue
        ],
        // Deep Emerald
        [
            Color(red: 0.0, green: 0.45, blue: 0.40),    // Deep Emerald
            Color(red: 0.0, green: 0.55, blue: 0.45),    // Rich Teal
            Color(red: 0.0, green: 0.40, blue: 0.35),    // Dark Emerald
            Color(red: 0.0, green: 0.45, blue: 0.40)     // Deep Emerald
        ],
        // Rich Amethyst
        [
            Color(red: 0.45, green: 0.15, blue: 0.80),   // Deep Purple
            Color(red: 0.50, green: 0.20, blue: 0.85),   // Rich Amethyst
            Color(red: 0.40, green: 0.10, blue: 0.75),   // Royal Purple
            Color(red: 0.45, green: 0.15, blue: 0.80)    // Deep Purple
        ],
        // Deep Ruby
        [
            Color(red: 0.80, green: 0.15, blue: 0.35),   // Deep Ruby
            Color(red: 0.85, green: 0.20, blue: 0.40),   // Rich Red
            Color(red: 0.75, green: 0.10, blue: 0.30),   // Dark Ruby
            Color(red: 0.80, green: 0.15, blue: 0.35)    // Deep Ruby
        ],
        // Ocean Depths
        [
            Color(red: 0.10, green: 0.35, blue: 0.65),   // Deep Ocean
            Color(red: 0.15, green: 0.40, blue: 0.70),   // Rich Marine
            Color(red: 0.05, green: 0.30, blue: 0.60),   // Dark Ocean
            Color(red: 0.10, green: 0.35, blue: 0.65)    // Deep Ocean
        ],
        // Imperial Purple
        [
            Color(red: 0.35, green: 0.15, blue: 0.55),   // Deep Imperial
            Color(red: 0.40, green: 0.20, blue: 0.60),   // Rich Purple
            Color(red: 0.30, green: 0.10, blue: 0.50),   // Dark Imperial
            Color(red: 0.35, green: 0.15, blue: 0.55)    // Deep Imperial
        ],
        // Midnight Indigo
        [
            Color(red: 0.20, green: 0.25, blue: 0.70),   // Deep Indigo
            Color(red: 0.25, green: 0.30, blue: 0.75),   // Rich Midnight
            Color(red: 0.15, green: 0.20, blue: 0.65),   // Dark Indigo
            Color(red: 0.20, green: 0.25, blue: 0.70)    // Deep Indigo
        ]
    ]
    
    init() {
        let initialColors = Self.gradientPresets[0]
        self.gradientColors = initialColors
        self.primaryColor = initialColors[0]
        
        // Update with current license info if available
        updateFromAppState()
    }
    
    func updateFromAppState() {
        let appState = AppStateManager.shared
        
        if case .valid = appState.licenseStatus, let info = appState.licenseInfo {
            // Update user info
            let emailComponents = info.email.split(separator: "@")
            if let name = emailComponents.first {
                userName = name.capitalized
            }
            userEmail = info.email
            
            // Update license info
            if let licenseKey = appState.getLicenseKey() {
                // Format license key for display (e.g., "ABCD-1234" -> "1234")
                licenseCode = String(licenseKey.suffix(4))
            }
            
            // Update dates
            memberSince = info.createdAt.formatted(.dateTime.month().year())
            licenseValidity = "Lifetime"
        }
    }
    
    func randomizeTheme() {
        // Pick a random preset
        let newColors = Self.gradientPresets.randomElement() ?? gradientColors
        withAnimation(.easeInOut(duration: 0.3)) {  // Faster color transition
            gradientColors = newColors
            primaryColor = newColors[0]
        }
    }
} 
