//
//  OnboardingSix+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension OnboardingSixView {
    
    // MARK: - Computed properties:
    
    /// An array of the features to display:
    var features: [NT_Feature] {
        .init(NT_Feature.allCases.prefix(4))
    }
    
    /// Title of the 'Get Started' button:
    var getStartedTitle: String {
        currentFeature == .globalStyleguide ? "Get Started" : "Next"
    }
}
