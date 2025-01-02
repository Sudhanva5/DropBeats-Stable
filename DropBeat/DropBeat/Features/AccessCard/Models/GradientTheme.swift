import SwiftUI

struct GradientTheme: Identifiable {
    let id = UUID()
    let colors: [Color]
    let name: String
    
    var gradient: LinearGradient {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static let themes: [GradientTheme] = [
        GradientTheme(
            colors: [
                Color(red: 0.98, green: 0.36, blue: 0.35),
                Color(red: 0.98, green: 0.62, blue: 0.27)
            ],
            name: "Sunset"
        ),
        GradientTheme(
            colors: [
                Color(red: 0.45, green: 0.73, blue: 0.98),
                Color(red: 0.35, green: 0.47, blue: 0.98)
            ],
            name: "Ocean"
        ),
        GradientTheme(
            colors: [
                Color(red: 0.82, green: 0.35, blue: 0.98),
                Color(red: 0.98, green: 0.35, blue: 0.73)
            ],
            name: "Berry"
        ),
        GradientTheme(
            colors: [
                Color(red: 0.35, green: 0.98, blue: 0.62),
                Color(red: 0.35, green: 0.91, blue: 0.98)
            ],
            name: "Mint"
        )
    ]
} 