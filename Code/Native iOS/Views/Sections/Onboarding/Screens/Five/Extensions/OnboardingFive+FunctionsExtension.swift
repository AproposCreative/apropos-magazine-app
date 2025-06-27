//
//  OnboardingFive+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension OnboardingFiveView {
    
    // MARK: - Functions:
    
    /// An array of the features to display that are part of the given group of the features:
    func features(_ group: NT_FeatureGroup) -> [NT_Feature] {
        group.features
    }
    
    /// Returns the title of the given feature:
    func title(_ feature: NT_Feature) -> String {
        feature.title
    }
    
    /// Returns the subtitle of the given feature:
    func subtitle(_ feature: NT_Feature) -> String {
        feature.subtitle
    }
    
    /// Returns the icon of the given feature:
    func icon(_ feature: NT_Feature) -> String {
        feature.icon
    }
    
    /// Returns the scale effect of the content in the given phase (Needed to add the scroll transition when scrolling between the different features):
    nonisolated func scaleEffect(inPhase phase: ScrollTransitionPhase) -> Double {
        phase.isIdentity ? 1 : 0.8
    }
    
    @ViewBuilder
    func groupTitle(_ group: NT_FeatureGroup) -> some View {
        switch currentGroup {
        case .none,
                .first,
                .second:
            Text("Supercharge Your \(Text("iOS App Project").foregroundStyle(groupTitleGradient)) 🚀")
        }
    }
    
    /// Moves the users to the next screen or simply dismisses the view based on the group of the features that is currently shown:
    func getStarted() {
        
        /// Firstly switching on the group of the features that is currently shown to perform the right action:
        switch currentGroup {
        case .first:
            
            /// If it's the first one, then moving the users to the second group of the features by updating the 'currentGroup' property with the value of the second feature group:
            currentGroup = .second
        case .second:
            
            /// If it's the second one, then simply dismissing the view because there are no other groups of the features displayed:
            dismiss()
        case .none:
            
            /// If none of the above, then showing the first group of the features by updating the 'currentGroup' property with the value of the first group of the features:
            currentGroup = .first
        }
    }
}
