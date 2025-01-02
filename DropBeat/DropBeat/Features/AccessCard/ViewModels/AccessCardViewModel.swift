import SwiftUI

class AccessCardViewModel: ObservableObject {
    @Published var primaryColor: Color
    @Published var gradientColors: [Color]
    
    // User info
    @Published var userName: String = "Sudhanva Acharya"
    @Published var userEmail: String = "sudhanv...mail.com"
    
    // License info
    @Published var licensePrefix: String = "DB"
    @Published var licenseYear: String = "2024"
    @Published var licenseCode: String = "WEXS"
    @Published var licenseValidity: String = "Lifetime"
    @Published var memberSince: String = "January 2024"
    
    // MARK: - Gradient Presets
    private static let gradientPresets: [[Color]] = [
        // Sunset Orange to Pink
        [
            Color(red: 1.0, green: 0.36, blue: 0.35),   // Bright Coral Red
            Color(red: 1.0, green: 0.58, blue: 0.0),    // Deep Orange
            Color(red: 1.0, green: 0.33, blue: 0.58),   // Vibrant Hot Pink
            Color(red: 1.0, green: 0.36, blue: 0.35)    // Bright Coral Red
        ],
        // Royal Purple to Blue
        [
            Color(red: 0.58, green: 0.23, blue: 0.95),  // Bright Purple
            Color(red: 0.0, green: 0.47, blue: 1.0),    // Vibrant Blue
            Color(red: 0.45, green: 0.31, blue: 1.0),   // Deep Purple
            Color(red: 0.58, green: 0.23, blue: 0.95)   // Bright Purple
        ],
        // Ocean Blue to Purple
        [
            Color(red: 0.0, green: 0.47, blue: 1.0),    // Vibrant Blue
            Color(red: 0.52, green: 0.27, blue: 0.95),  // Medium Purple
            Color(red: 0.12, green: 0.53, blue: 1.0),   // Bright Ocean Blue
            Color(red: 0.0, green: 0.47, blue: 1.0)     // Vibrant Blue
        ],
        // Dark Green to Emerald
        [
            Color(red: 0.0, green: 0.50, blue: 0.25),   // Dark Forest Green
            Color(red: 0.0, green: 0.75, blue: 0.45),   // Emerald Green
            Color(red: 0.0, green: 0.55, blue: 0.35),   // Deep Green
            Color(red: 0.0, green: 0.50, blue: 0.25)    // Dark Forest Green
        ],
        // Rose Pink to Orange
        [
            Color(red: 1.0, green: 0.33, blue: 0.58),   // Vibrant Hot Pink
            Color(red: 1.0, green: 0.48, blue: 0.31),   // Bright Salmon Orange
            Color(red: 0.95, green: 0.27, blue: 0.51),  // Deep Pink
            Color(red: 1.0, green: 0.33, blue: 0.58)    // Vibrant Hot Pink
        ]
    ]
    
    init() {
        let initialColors = Self.gradientPresets[0]
        self.gradientColors = initialColors
        self.primaryColor = initialColors[0]
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
