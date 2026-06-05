import SwiftUI

enum AppMotion {
    static func spring(response: Double = 0.5, damping: Double = 0.84, reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(response: response, dampingFraction: damping)
    }

    static func easeOut(duration: Double, reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: duration)
    }

    static func easeInOut(duration: Double, reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: duration)
    }

    static func heroCarouselSpring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0)
    }
}

struct HeroScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct GlassTopBarScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum GlassTopBarScroll {
    static let fadeDistance: CGFloat = 32

    static func opacity(forScrollMinY minY: CGFloat, reduceMotion: Bool = false) -> CGFloat {
        if reduceMotion {
            return minY < -16 ? 1 : 0
        }
        return min(max(-minY / fadeDistance, 0), 1)
    }
}

struct GlassTopBarMaterial: View {
    let opacity: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(opacity)
            .frame(height: height)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ReduceMotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

struct StaggeredRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let baseDelay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : 16))
            .onAppear {
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(
                        .spring(response: 0.55, dampingFraction: 0.86)
                            .delay(baseDelay + Double(index) * 0.07)
                    ) {
                        isVisible = true
                    }
                }
            }
    }
}

struct HeroParallaxModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scrollOffset: CGFloat
    let height: CGFloat

    private var stretch: CGFloat {
        max(0, -scrollOffset)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : 1 + min(stretch / max(height, 1), 1) * 0.08, anchor: .center)
            .offset(y: reduceMotion ? 0 : stretch * 0.22)
    }
}

struct HeroTransitionSourceModifier: ViewModifier {
    let articleID: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: articleID, in: namespace)
        } else {
            content
        }
    }
}

struct ArticleHeaderRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isRevealed: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .scaleEffect(isRevealed ? 1 : (reduceMotion ? 1 : 1.035), anchor: .center)
    }
}

extension View {
    func appAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
    }

    func staggeredReveal(index: Int, baseDelay: Double = 0) -> some View {
        modifier(StaggeredRevealModifier(index: index, baseDelay: baseDelay))
    }

    func heroParallax(scrollOffset: CGFloat, height: CGFloat) -> some View {
        modifier(HeroParallaxModifier(scrollOffset: scrollOffset, height: height))
    }

    func heroTransitionSource(id: String, namespace: Namespace.ID?) -> some View {
        modifier(HeroTransitionSourceModifier(articleID: id, namespace: namespace))
    }

    func articleHeaderReveal(isRevealed: Binding<Bool>) -> some View {
        modifier(ArticleHeaderRevealModifier(isRevealed: isRevealed))
    }
}
