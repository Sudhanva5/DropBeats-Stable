import SwiftUI

struct AccessCardView: View {
    @EnvironmentObject private var viewModel: AccessCardViewModel
    @State private var rotation: Double = 0
    private let animationDuration: Double = 8  // Slower, smoother rotation
    
    private var meshGradient: AnyShapeStyle {
        let angle = Angle(degrees: rotation)
        let radius: CGFloat = 0.5
        
        // Calculate rotated points
        let startX = 0.5 + radius * cos(angle.radians)
        let startY = 0.5 + radius * sin(angle.radians)
        let endX = 0.5 - radius * cos(angle.radians)
        let endY = 0.5 - radius * sin(angle.radians)
        
        return AnyShapeStyle(
            LinearGradient(
                colors: viewModel.gradientColors,
                startPoint: UnitPoint(x: startX, y: startY),
                endPoint: UnitPoint(x: endX, y: endY)
            )
        )
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background
            Color(hex: "FFF7EA")
                .opacity(0.95)
            
            // Decorative Element with mesh gradient
            Image("dropbeats-decorative")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100)
                .foregroundStyle(meshGradient)
                .position(x: 210, y: 85)
            
            // Content Container
            VStack(alignment: .leading, spacing: 0) {
                // Top content
                Image("dropbeats-mini-logo")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 18)
                    .foregroundColor(viewModel.primaryColor)
                
                Spacer()
                
                // Bottom content
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome")
                            .font(.system(size: 14))
                            .foregroundColor(viewModel.primaryColor)
                        
                        Text(viewModel.userName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(viewModel.primaryColor)
                    }
                    
                    // License plate style box
                    HStack(spacing: 0) {
                        // Prefix section
                        Text(viewModel.licensePrefix)
                            .frame(width: 32)
                            .font(.system(size: 12, weight: .medium))
                        
                        // First separator
                        Rectangle()
                            .frame(width: 1, height: 20)
                            .foregroundColor(viewModel.primaryColor)
                        
                        // Year section
                        Text(viewModel.licenseYear)
                            .frame(width: 44)
                            .font(.system(size: 12, weight: .medium))
                        
                        // Second separator
                        Rectangle()
                            .frame(width: 1, height: 20)
                            .foregroundColor(viewModel.primaryColor)
                        
                        // Unique code section
                        Text(viewModel.licenseCode)
                            .frame(width: 48)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(height: 20)
                    .tracking(0.5)
                    .foregroundColor(viewModel.primaryColor)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(viewModel.primaryColor, lineWidth: 1)
                    )
                }
            }
            .padding(16)
        }
        .frame(width: 260, height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            withAnimation(
                .linear(duration: 2)  // Even faster rotation
                .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
    }
}

// Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
