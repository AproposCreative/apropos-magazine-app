//
//  OnboardingNine+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension OnboardingNineView {
    
    // MARK: - Computed properties:
    
    /// An actual image to display:
    var image: Image {
        .init(.onboarding9)
    }
    
    /// Starting color of the gradient of the background of the image that is displayed:
    var imageBackgroundGradientStart: Color {
        .blueGradientStart.opacity(imageBackgroundOpacity)
    }
    
    /// Ending color of the gradient of the background of the image that is displayed:
    var imageBackgroundGradientEnd: Color {
        .blueGradientEnd.opacity(imageBackgroundOpacity)
    }
    
    // MARK: - Private computed properties:
    
    /// Opacity of the background of the image that is displayed:
    private var imageBackgroundOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.12
    }
}
