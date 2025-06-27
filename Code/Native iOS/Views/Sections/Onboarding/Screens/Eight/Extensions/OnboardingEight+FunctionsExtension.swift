//
//  OnboardingEight+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension OnboardingEightView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given feature:
    func title(_ feature: NT_Feature) -> String {
        feature.title
    }
    
    /// Returns the subtitle of the given feature:
    func subtitle(_ feature: NT_Feature) -> String {
        feature.subtitle
    }
    
    /// Returns the image of the given feature:
    func image(_ feature: NT_Feature) -> Image {
        .init(feature.onboarding8Image)
    }
    
    /// Dismisses the view:
    func getStarted() {
        
        /// Dismissing the view:
        dismiss()
    }
}
