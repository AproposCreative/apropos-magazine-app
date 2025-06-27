//
//  OnboardingFive+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension OnboardingFiveView {
    
    // MARK: - Computed properties:
    
    /// An array of the groups of the features to display:
    var groups: [NT_FeatureGroup] {
        NT_FeatureGroup.allCases
    }
    
    /// Title of the 'Get Started' button:
    var getStartedTitle: String {
        currentGroup == .second ? "Get Started" : "Next"
    }
    
    /// Gradient of the title of the group of the features:
    var groupTitleGradient: LinearGradient {
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
