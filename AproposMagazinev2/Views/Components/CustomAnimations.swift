import SwiftUI

// MARK: - Custom Transitions

struct SlideTransition: ViewModifier {
    let edge: Edge
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .transition(.asymmetric(
                insertion: .move(edge: edge).combined(with: .opacity),
                removal: .move(edge: edge).combined(with: .opacity)
            ))
    }
}

struct ScaleTransition: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 1.0 : 0.8)
            .opacity(isActive ? 1.0 : 0.0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isActive)
    }
}

struct FadeTransition: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}

// MARK: - Custom Animations

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .opacity(isPulsing ? 0.8 : 1.0)
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

struct ShakeAnimation: ViewModifier {
    @State private var isShaking = false
    
    func body(content: Content) -> some View {
        content
            .offset(x: isShaking ? 5 : 0)
            .animation(
                .easeInOut(duration: 0.1)
                .repeatCount(3, autoreverses: true),
                value: isShaking
            )
    }
    
    func trigger() {
        isShaking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isShaking = false
        }
    }
}

struct BounceAnimation: ViewModifier {
    @State private var isBouncing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isBouncing ? 1.2 : 1.0)
            .animation(
                .spring(response: 0.3, dampingFraction: 0.6)
                .repeatCount(1, autoreverses: true),
                value: isBouncing
            )
    }
    
    func trigger() {
        isBouncing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isBouncing = false
        }
    }
}

struct RotateAnimation: ViewModifier {
    @State private var isRotating = false
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(
                .linear(duration: 2.0)
                .repeatForever(autoreverses: false),
                value: isRotating
            )
            .onAppear {
                isRotating = true
            }
    }
}

// MARK: - Loading Animations

struct LoadingDots: View {
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .offset(y: animationOffset)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: animationOffset
                    )
            }
        }
        .onAppear {
            animationOffset = -10
        }
    }
}

struct LoadingSpinner: View {
    @State private var isRotating = false
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.blue, lineWidth: 3)
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(
                .linear(duration: 1.0)
                .repeatForever(autoreverses: false),
                value: isRotating
            )
            .onAppear {
                isRotating = true
            }
    }
}

// MARK: - Page Transitions

struct PageTransition: ViewModifier {
    let direction: TransitionDirection
    let isActive: Bool
    
    enum TransitionDirection {
        case left, right, up, down
    }
    
    func body(content: Content) -> some View {
        content
            .transition(.asymmetric(
                insertion: slideTransition(for: direction),
                removal: slideTransition(for: direction, reverse: true)
            ))
    }
    
    private func slideTransition(for direction: TransitionDirection, reverse: Bool = false) -> AnyTransition {
        let edge: Edge
        switch direction {
        case .left: edge = reverse ? .trailing : .leading
        case .right: edge = reverse ? .leading : .trailing
        case .up: edge = reverse ? .bottom : .top
        case .down: edge = reverse ? .top : .bottom
        }
        
        return .move(edge: edge).combined(with: .opacity)
    }
}

// MARK: - Card Animations

struct CardFlipAnimation: ViewModifier {
    @State private var isFlipped = false
    
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(isFlipped ? 180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
            .animation(.easeInOut(duration: 0.6), value: isFlipped)
    }
    
    func flip() {
        isFlipped.toggle()
    }
}

struct CardHoverAnimation: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .shadow(
                color: .black.opacity(isHovered ? 0.2 : 0.1),
                radius: isHovered ? 10 : 5,
                x: 0,
                y: isHovered ? 5 : 2
            )
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isHovered.toggle()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isHovered.toggle()
                }
            }
    }
}

// MARK: - Button Animations

struct ButtonPressAnimation: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onTapGesture {
                isPressed = true
                HapticManager.shared.lightImpact()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                }
            }
    }
}

struct ButtonGlowAnimation: ViewModifier {
    @State private var isGlowing = false
    
    func body(content: Content) -> some View {
        content
            .shadow(
                color: .blue.opacity(isGlowing ? 0.6 : 0.0),
                radius: isGlowing ? 10 : 0,
                x: 0,
                y: 0
            )
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true),
                value: isGlowing
            )
            .onAppear {
                isGlowing = true
            }
    }
}

// MARK: - List Animations

struct ListItemAnimation: ViewModifier {
    let index: Int
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : 0.0)
            .offset(x: isVisible ? 0 : 50)
            .animation(
                .easeOut(duration: 0.5)
                .delay(Double(index) * 0.1),
                value: isVisible
            )
            .onAppear {
                isVisible = true
            }
    }
}

// MARK: - Text Animations

struct TypewriterAnimation: ViewModifier {
    let text: String
    @State private var displayedText = ""
    @State private var currentIndex = 0
    
    func body(content: Content) -> some View {
        Text(displayedText)
            .onAppear {
                startTypewriter()
            }
    }
    
    private func startTypewriter() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if currentIndex < text.count {
                let index = text.index(text.startIndex, offsetBy: currentIndex)
                displayedText += String(text[index])
                currentIndex += 1
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - SwiftUI Extensions

extension View {
    func slideTransition(edge: Edge, isActive: Bool) -> some View {
        self.modifier(SlideTransition(edge: edge, isActive: isActive))
    }
    
    func scaleTransition(isActive: Bool) -> some View {
        self.modifier(ScaleTransition(isActive: isActive))
    }
    
    func fadeTransition(isActive: Bool) -> some View {
        self.modifier(FadeTransition(isActive: isActive))
    }
    
    func pulseAnimation() -> some View {
        self.modifier(PulseAnimation())
    }
    
    func shakeAnimation() -> some View {
        self.modifier(ShakeAnimation())
    }
    
    func bounceAnimation() -> some View {
        self.modifier(BounceAnimation())
    }
    
    func rotateAnimation() -> some View {
        self.modifier(RotateAnimation())
    }
    
    func pageTransition(direction: PageTransition.TransitionDirection, isActive: Bool) -> some View {
        self.modifier(PageTransition(direction: direction, isActive: isActive))
    }
    
    func cardFlipAnimation() -> some View {
        self.modifier(CardFlipAnimation())
    }
    
    func cardHoverAnimation() -> some View {
        self.modifier(CardHoverAnimation())
    }
    
    func buttonPressAnimation() -> some View {
        self.modifier(ButtonPressAnimation())
    }
    
    func buttonGlowAnimation() -> some View {
        self.modifier(ButtonGlowAnimation())
    }
    
    func listItemAnimation(index: Int) -> some View {
        self.modifier(ListItemAnimation(index: index))
    }
    
    func typewriterAnimation(text: String) -> some View {
        self.modifier(TypewriterAnimation(text: text))
    }
}

// MARK: - Animation Presets

struct AnimationPresets {
    static let smooth = Animation.easeInOut(duration: 0.3)
    static let spring = Animation.spring(response: 0.6, dampingFraction: 0.8)
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let slow = Animation.easeInOut(duration: 0.8)
    static let fast = Animation.easeInOut(duration: 0.15)
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        // Loading animations
        VStack(spacing: 20) {
            LoadingDots()
            LoadingSpinner()
        }
        
        // Button animations
        VStack(spacing: 20) {
            Button("Press Me") {}
                .buttonPressAnimation()
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Button("Glow Button") {}
                .buttonGlowAnimation()
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        
        // Card animations
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange)
                .frame(width: 100, height: 100)
                .cardHoverAnimation()
            
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple)
                .frame(width: 100, height: 100)
                .pulseAnimation()
        }
        
        // Typewriter animation
        Text("")
            .typewriterAnimation(text: "Velkommen til Apropos Magazine!")
            .font(.headline)
    }
    .padding()
}
