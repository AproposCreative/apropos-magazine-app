//
//  OnboardingThirteen+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension OnboardingThirteenView {
    
    // MARK: - Computed properties:
    
    /// An array of the features to display:
    var features: [NT_Feature] {
        .init(NT_Feature.allCases.prefix(2))
    }
    
    /// Title of the 'Get Started' button:
    var getStartedTitle: String {
        currentFeature == .nativeDesign ? "Get Started" : "Next"
    }
    
    /// Gradient of the background of the view:
    var backgroundGradient: LinearGradient {
        .init(
            colors: [
                .blueGradientStart,
                .blueGradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
