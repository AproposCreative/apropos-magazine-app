import SwiftUI

struct SwipeBackModifier: ViewModifier {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.dismiss) private var dismiss
    let threshold: CGFloat
    let isEnabled: Bool
    
    init(threshold: CGFloat = 50, isEnabled: Bool = true) {
        self.threshold = threshold
        self.isEnabled = isEnabled
    }
    
    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture()
                    .onEnded { value in
                        guard isEnabled else { return }
                        
                        if value.translation.width > threshold {
                            // Swipe right detected
                            withAnimation(.easeInOut(duration: 0.3)) {
                                // Try dismiss first (iOS 15+), fallback to presentationMode
                                if #available(iOS 15.0, *) {
                                    dismiss()
                                } else {
                                    presentationMode.wrappedValue.dismiss()
                                }
                            }
                        }
                    }
            )
    }
}

extension View {
    /// Adds swipe-to-go-back functionality to the view
    /// - Parameters:
    ///   - threshold: The minimum distance required to trigger the back action (default: 50)
    ///   - isEnabled: Whether the gesture is enabled (default: true)
    func swipeToGoBack(threshold: CGFloat = 50, isEnabled: Bool = true) -> some View {
        self.modifier(SwipeBackModifier(threshold: threshold, isEnabled: isEnabled))
    }
    
    /// Adds swipe-to-go-back functionality only for pushed views (not tab content)
    func swipeToGoBackIfPushed() -> some View {
        // Only enable swipe back if this view is presented modally or pushed
        // Tab content should not have swipe back gestures
        self.swipeToGoBack(isEnabled: false) // Disabled by default for tab content
    }
}
