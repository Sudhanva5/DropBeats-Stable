import SwiftUI

struct AccessCardView: View {
    @EnvironmentObject private var viewModel: AccessCardViewModel
    @State private var rotation: Double = 0
    @State private var isHovering: Bool = false
    @State private var mouseLocation: CGPoint = .zero
    private let animationDuration: Double = 3
    
    private var meshGradient: AnyShapeStyle {
        let angle = Angle(degrees: rotation)
        let radius: CGFloat = 1.0
        
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
    
    private var shimmerGradient: LinearGradient {
        let mouseX = mouseLocation.x / 230 // Normalize to 0-1 range
        let mouseY = mouseLocation.y / 340
        
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(0.0), location: 0),
                .init(color: .white.opacity(0.0), location: max(0, mouseX - 0.3)),
                .init(color: .white.opacity(0.4), location: mouseX),
                .init(color: .white.opacity(0.0), location: min(1, mouseX + 0.3)),
                .init(color: .white.opacity(0.0), location: 1),
            ],
            startPoint: UnitPoint(x: 0, y: mouseY),
            endPoint: UnitPoint(x: 1, y: mouseY)
        )
    }
    
    private func calculateTilt(for location: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        let centerX = size.width / 2
        let centerY = size.height / 2
        
        let maxTilt: Double = 3 // Maximum tilt angle in degrees
        
        let xTilt = maxTilt * (location.x - centerX) / centerX
        let yTilt = maxTilt * (location.y - centerY) / centerY
        
        return (-yTilt, xTilt) // Inverted for natural feel
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Background
                Color(hex: "FFF7EA")
                    .opacity(0.9)
                
                // Shimmer effect
                shimmerGradient
                    .opacity(isHovering ? 1 : 0)
                    .blendMode(.overlay)
                    .animation(
                        .interpolatingSpring(stiffness: 150, damping: 15),
                        value: mouseLocation
                    )
                
                // Decorative Element with mesh gradient
                Image("dropbeats-decorative")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100)
                    .foregroundStyle(meshGradient)
                    .position(x: 180, y: 85)
                
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
                    VStack(alignment: .leading, spacing: 20) {
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
                            // First section (B7E2 from B7E21F8B)
                            Text(viewModel.licenseKey.prefix(4))
                                .frame(width: 44)
                                .font(.system(size: 11, weight: .medium))
                            
                            // First separator
                            Rectangle()
                                .frame(width: 1, height: 20)
                                .foregroundColor(viewModel.primaryColor)
                            
                            // Second section (C928 from C9284376)
                            Text(viewModel.licenseKey.dropFirst(9).prefix(4))
                                .frame(width: 44)
                                .font(.system(size: 11, weight: .medium))
                            
                            // Second separator
                            Rectangle()
                                .frame(width: 1, height: 20)
                                .foregroundColor(viewModel.primaryColor)
                            
                            // Third section (8611 from 86119A9F)
                            Text(viewModel.licenseKey.dropFirst(18).prefix(4))
                                .frame(width: 44)
                                .font(.system(size: 11, weight: .medium))
                            
                            // Third separator
                            Rectangle()
                                .frame(width: 1, height: 20)
                                .foregroundColor(viewModel.primaryColor)
                            
                            // Fourth section (EC87 from EC878EDA)
                            Text(viewModel.licenseKey.dropFirst(27).prefix(4))
                                .frame(width: 44)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(height: 18)
                        .tracking(0.5)
                        .foregroundColor(viewModel.primaryColor)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(viewModel.primaryColor, lineWidth: 1)
                        )
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 230, height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(isHovering ? 0.15 : 0.1), radius: isHovering ? 8 : 5, x: 0, y: isHovering ? 4 : 2)
        .rotation3DEffect(
            .degrees(isHovering ? calculateTilt(for: mouseLocation, in: CGSize(width: 230, height: 340)).x : 0),
            axis: (x: 1, y: 0, z: 0)
        )
        .rotation3DEffect(
            .degrees(isHovering ? calculateTilt(for: mouseLocation, in: CGSize(width: 230, height: 340)).y : 0),
            axis: (x: 0, y: 1, z: 0)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                mouseLocation = location
            case .ended:
                mouseLocation = CGPoint(x: 115, y: 170) // Center point
            }
        }
        .onAppear {
            // Start rotation animation immediately
            withAnimation(
                .linear(duration: animationDuration)
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
