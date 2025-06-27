//
//  OnboardingThree+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension OnboardingThreeView {
    
    // MARK: - Computed properties:
    
    /// Gradient of the title:
    var titleGradient: LinearGradient {
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
