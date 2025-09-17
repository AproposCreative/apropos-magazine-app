import SwiftUI
import UIKit

struct EnhancedSwipeBackModifier: ViewModifier {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    let threshold: CGFloat
    let hapticFeedback: Bool
    let isEnabled: Bool
    
    init(threshold: CGFloat = 50, hapticFeedback: Bool = true, isEnabled: Bool = true) {
        self.threshold = threshold
        self.hapticFeedback = hapticFeedback
        self.isEnabled = isEnabled
    }
    
    func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .opacity(1.0 - abs(dragOffset) / 300.0)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard isEnabled else { return }
                        
                        if value.translation.width > 0 {
                            isDragging = true
                            dragOffset = value.translation.width * SwipeBackConfiguration.dragDampingFactor
                        }
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        
                        isDragging = false
                        
                        if value.translation.width > threshold {
                            // Swipe right detected - go back
                            if hapticFeedback {
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                            }
                            
                            withAnimation(.easeInOut(duration: 0.3)) {
                                dragOffset = UIScreen.main.bounds.width
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                // Try dismiss first (iOS 15+), fallback to presentationMode
                                if #available(iOS 15.0, *) {
                                    dismiss()
                                } else {
                                    presentationMode.wrappedValue.dismiss()
                                }
                            }
                        } else {
                            // Reset position
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .animation(.easeInOut(duration: 0.2), value: isDragging)
    }
}

extension View {
    /// Adds enhanced swipe-to-go-back functionality with visual feedback
    /// - Parameters:
    ///   - threshold: The minimum distance required to trigger the back action (default: 50)
    ///   - hapticFeedback: Whether to provide haptic feedback (default: true)
    ///   - isEnabled: Whether the gesture is enabled (default: true)
    func enhancedSwipeToGoBack(threshold: CGFloat = 50, hapticFeedback: Bool = true, isEnabled: Bool = true) -> some View {
        self.modifier(EnhancedSwipeBackModifier(threshold: threshold, hapticFeedback: hapticFeedback, isEnabled: isEnabled))
    }
    
    /// Adds enhanced swipe-to-go-back functionality only for detail views
    func enhancedSwipeToGoBackForDetail() -> some View {
        self.enhancedSwipeToGoBack(isEnabled: false) // Disabled by default for tab content
    }
}
