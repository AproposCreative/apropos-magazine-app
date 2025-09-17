import SwiftUI

struct ShimmerConfig {
    var tint: Color
    var highlight: Color
    var blur: CGFloat = 0
    var highlightOpacity: CGFloat = 1
    var speed: CGFloat = 2
}

@available(iOS 15.0, *)
struct ShimmerEffect: ViewModifier {
    @State private var config: ShimmerConfig
    @State private var phase: CGFloat = -0.5

    init(config: ShimmerConfig) {
        self._config = State(initialValue: config)
    }

    func body(content: Content) -> some View {
        content
            .modifier(
                ShimmerEffectHelper(
                    config: config,
                    phase: phase
                )
            )
            .onAppear {
                startAnimation()
            }
    }

    func startAnimation() {
        withAnimation(
            .linear(duration: config.speed)
            .repeatForever(autoreverses: false)
        ) {
            phase = 1.5
        }
    }
}

@available(iOS 15.0, *)
fileprivate struct ShimmerEffectHelper: ViewModifier {
    var config: ShimmerConfig
    var phase: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        let TINT = config.tint.opacity(colorScheme == .dark ? 0.2 : 0.7)
        let HIGHLIGHT = config.highlight.opacity(config.highlightOpacity)

        content
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: HIGHLIGHT, location: phase - 0.2),
                                .init(color: HIGHLIGHT, location: phase),
                                .init(color: HIGHLIGHT, location: phase + 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .background(TINT)
    }
}

extension View {
    @ViewBuilder
    func shimmer(config: ShimmerConfig) -> some View {
        if #available(iOS 15.0, *) {
            self.modifier(ShimmerEffect(config: config))
        } else {
            self
        }
    }
} 