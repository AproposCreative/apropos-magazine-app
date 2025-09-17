import SwiftUI
import Shimmer

struct LoadingView: View {
    
    // MARK: - Properties
    
    private let isShowing: Bool
    private let title: String?
    private let color: Color
    private let scale: Double
    
    init(
        isShowing: Bool,
        title: String? = nil,
        color: Color = .accentColor,
        scale: Double = 1.0
    ) {
        self.isShowing = isShowing
        self.title = title
        self.color = color
        self.scale = scale
    }
    
    // MARK: - View
    
    var body: some View {
        if isShowing {
            VStack(spacing: 16) {
                // Shimmer loading effect
                VStack(spacing: 12) {
                    // Circular shimmer
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .shimmering(
                            active: true,
                            animation: .linear(duration: 1.5).repeatForever(autoreverses: false),
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.white.opacity(0.6),
                                Color.clear
                            ]),
                            bandSize: 0.3
                        )
                    
                    if title != nil {
                        // Text shimmer
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 150, height: 16)
                            .shimmering(
                                active: true,
                                animation: .linear(duration: 1.5).repeatForever(autoreverses: false),
                                gradient: Gradient(colors: [
                                    Color.clear,
                                    Color.white.opacity(0.6),
                                    Color.clear
                                ]),
                                bandSize: 0.3
                            )
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 32) {
        LoadingView(
            isShowing: true,
            title: "Henter artikler..."
        )
        
        LoadingView(
            isShowing: true,
            title: "AI genererer anbefalinger...",
            color: .purple
        )
        
        LoadingView(
            isShowing: true
        )
    }
    .padding()
} 
