//
//  OnboardingThirteen+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension OnboardingThirteenView {
    
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
        .init(feature.onboarding13Image)
    }
    
    /// Moves the users to the next screen or simply dismisses the view based on the feature that is currently shown:
    func getStarted() {
        
        /// Firstly switching on the feature that is currently shown to perform the right action:
        switch currentFeature {
        case .latestTechnologies:
            
            /// If it's the first one, then moving the users to the second feature by updating the 'currentFeature' property with the value of the second feature:
            currentFeature = .nativeDesign
        case .nativeDesign:
            
            /// If it's the second one, then simply dismissing the view because there are no other features displayed:
            dismiss()
        case .reusableComponents,
                .globalStyleguide,
                .fullyAccessible,
                .scalableSourceCode:
            
            /// If it's either the third, the fourth, the fifth, or the sixth one, then simply breaking because they simply aren't displayed here:
            break
        case .none:
            
            /// If none of the above, then showing the first feature by updating the 'currentFeature' property with the value of the first feature:
            currentFeature = .latestTechnologies
        }
    }
}
