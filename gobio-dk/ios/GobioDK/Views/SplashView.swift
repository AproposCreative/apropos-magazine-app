import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var opacity = 0.0
    @State private var scale = 0.8
    
    var body: some View {
        if isActive {
            ContentView()
        } else {
            ZStack {
                Color(hex: "0F0F23")
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Image(systemName: "film.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "6366F1"), Color(hex: "818CF8")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    HStack(spacing: 0) {
                        Text("gobio")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(".dk")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "F59E0B"))
                    }
                    
                    Text("Din danske biografguide")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
                .scaleEffect(scale)
                .opacity(opacity)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    opacity = 1.0
                    scale = 1.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isActive = true
                    }
                }
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
