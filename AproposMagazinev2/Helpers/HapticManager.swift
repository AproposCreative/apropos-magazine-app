import UIKit
import SwiftUI

class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    // MARK: - Impact Feedback
    
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }
    
    func lightImpact() {
        impact(style: .light)
    }
    
    func mediumImpact() {
        impact(style: .medium)
    }
    
    func heavyImpact() {
        impact(style: .heavy)
    }
    
    // MARK: - Notification Feedback
    
    func success() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }
    
    func warning() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)
    }
    
    func error() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
    }
    
    // MARK: - Selection Feedback
    
    func selection() {
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
    }
    
    // MARK: - Custom Patterns
    
    func doubleTap() {
        lightImpact()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.lightImpact()
        }
    }
    
    func longPress() {
        mediumImpact()
    }
    
    func buttonPress() {
        lightImpact()
    }
    
    func scroll() {
        // Only trigger occasionally to avoid overwhelming
        if Int.random(in: 1...10) == 1 {
            lightImpact()
        }
    }
}

// MARK: - SwiftUI Extensions

extension View {
    func hapticFeedback(_ action: @escaping () -> Void) -> some View {
        self.onTapGesture {
            HapticManager.shared.buttonPress()
            action()
        }
    }
    
    func hapticScroll() -> some View {
        self.onAppear {
            HapticManager.shared.scroll()
        }
    }
}
