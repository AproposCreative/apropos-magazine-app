//
//  OnboardingOne+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension OnboardingOneView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given feature:
    func title(_ feature: NT_Feature) -> String {
        feature.title
    }
    
    /// Returns the subtitle of the given feature:
    func subtitle(_ feature: NT_Feature) -> String {
        feature.subtitle
    }
    
    /// Returns the starting color of the gradient of the given feature if applicable:
    func gradientStart(_ feature: NT_Feature) -> Color {
        feature.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given feature if applicable:
    func gradientEnd(_ feature: NT_Feature) -> Color {
        feature.gradientEnd
    }
    
    /// Returns the icon of the given feature:
    func icon(_ feature: NT_Feature) -> String {
        feature.icon
    }
    
    /// Dismisses the view:
    func getStarted() {
        
        /// Dismissing the view:
        dismiss()
    }
}
