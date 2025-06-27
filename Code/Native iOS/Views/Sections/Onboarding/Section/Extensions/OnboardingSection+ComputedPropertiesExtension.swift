//
//  OnboardingSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension OnboardingSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_OnboardingScreen] {
        NT_OnboardingScreen.allCases
    }
}
