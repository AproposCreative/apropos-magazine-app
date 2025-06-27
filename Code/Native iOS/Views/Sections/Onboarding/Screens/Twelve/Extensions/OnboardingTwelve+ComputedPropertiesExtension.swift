//
//  OnboardingTwelve+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension OnboardingTwelveView {
    
    // MARK: - Computed properties:
    
    /// An array of the features to display:
    var features: [NT_Feature] {
        .init(NT_Feature.allCases.prefix(3))
    }
    
    /// Title of the view to display that is based on the feature that is currently shown:
    var title: String {
        currentFeature?.title ?? ""
    }
    
    /// Subtitle of the view to display that is based on the feature that is currently shown:
    var subtitle: String {
        currentFeature?.subtitle ?? ""
    }
    
    /// Title of the 'Get Started' button:
    var getStartedTitle: String {
        currentFeature == .reusableComponents ? "Get Started" : "Next"
    }
    
    /// Horizontal padding around the content of the view:
    var horizontalPadding: Double {
        16
    }
}
