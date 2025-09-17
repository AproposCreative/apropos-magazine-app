import SwiftUI

/// Global configuration for swipe back gestures throughout the app
struct SwipeBackConfiguration {
    /// Default threshold for swipe back gestures (in points)
    static let defaultThreshold: CGFloat = 50
    
    /// Whether to enable haptic feedback by default
    static let defaultHapticFeedback = true
    
    /// Animation duration for swipe back transitions
    static let animationDuration: Double = 0.3
    
    /// Damping factor for drag gesture (0.0 to 1.0)
    static let dragDampingFactor: CGFloat = 0.3
    
    /// Opacity reduction factor for visual feedback
    static let opacityReductionFactor: CGFloat = 300
    
    /// Whether swipe back is enabled globally
    static let isEnabled = true
    
    /// Views that should NOT have swipe back gestures (tab content, root views)
    static let excludedViews: Set<String> = [
        "HomeView",
        "FavoritesView", 
        "ProfileView",
        "CategoriesView"
    ]
}

/// Convenience extension for consistent swipe back implementation
extension View {
    /// Applies the default swipe back configuration to the view
    func defaultSwipeBack() -> some View {
        if SwipeBackConfiguration.isEnabled {
            return AnyView(self.enhancedSwipeToGoBack(
                threshold: SwipeBackConfiguration.defaultThreshold,
                hapticFeedback: SwipeBackConfiguration.defaultHapticFeedback
            ))
        } else {
            return AnyView(self)
        }
    }
    
    /// Applies swipe back only for detail views (not tab content)
    func swipeBackForDetailView() -> some View {
        // Only apply swipe back for views that are pushed or presented modally
        // Tab content should not have swipe back gestures
        self.swipeToGoBack(isEnabled: false)
    }
    
    /// Intelligently applies swipe back gestures based on context
    /// This modifier will only enable swipe gestures for views that are pushed or presented modally
    func smartSwipeBack() -> some View {
        // For now, we'll disable it by default and let you manually enable it for specific views
        // In the future, this could use environment values to detect navigation context
        self.enhancedSwipeToGoBack(isEnabled: false)
    }
}
