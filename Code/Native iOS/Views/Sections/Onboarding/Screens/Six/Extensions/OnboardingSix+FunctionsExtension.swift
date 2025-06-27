//
//  OnboardingSix+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension OnboardingSixView {
    
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
        .init(feature.onboarding6Image)
    }
    
    /// Returns the alignment of the image of the given feature:
    func imageAlignment(_ feature: NT_Feature) -> Alignment {
        feature.imageAlignment
    }
    
    /// Returns the scale effect of the content in the given phase (Needed to add the scroll transition when scrolling between the different features):
    nonisolated func scaleEffect(inPhase phase: ScrollTransitionPhase) -> Double {
        phase.isIdentity ? 1 : 0.8
    }
    
    /// Moves the users to the next screen or simply dismisses the view based on the feature that is currently shown:
    func getStarted() {
        
        /// Firstly switching on the feature that is currently shown to perform the right action:
        switch currentFeature {
        case .latestTechnologies:
            
            /// If it's the first one, then moving the users to the second feature by updating the 'currentFeature' property with the value of the second feature:
            currentFeature = .nativeDesign
        case .nativeDesign:
            
            /// If it's the second one, then moving the users to the second feature by updating the 'currentFeature' property with the value of the third feature:
            currentFeature = .reusableComponents
        case .reusableComponents:
            
            /// If it's the third one, then moving the users to the second feature by updating the 'currentFeature' property with the value of the fourth feature:
            currentFeature = .globalStyleguide
        case .globalStyleguide:
            
            /// If it's the fourth one, then simply dismissing the view because there are no other features displayed:
            dismiss()
        case .fullyAccessible,
                .scalableSourceCode:
            
            /// If it's either the fifth or the sixth one, then simply breaking because they simply aren't displayed here:
            break
        case .none:
            
            /// If none of the above, then showing the first feature by updating the 'currentFeature' property with the value of the first feature:
            currentFeature = .latestTechnologies
        }
    }
}
