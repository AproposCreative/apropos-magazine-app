//
//  OnboardingEleven+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension OnboardingElevenView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given feature:
    func title(_ feature: NT_Feature) -> String {
        feature.title
    }
    
    /// Returns the subtitle of the given feature:
    func subtitle(_ feature: NT_Feature) -> String {
        feature.subtitle
    }
    
    /// Returns the title of the badge of the given feature:
    func badgeTitle(_ feature: NT_Feature) -> String {
        feature.badgeTitle
    }
    
    /// Returns the color of the given feature:
    func color(_ feature: NT_Feature) -> Color {
        feature.color
    }
    
    /// Returns the starting color of the gradient of the given feature if applicable:
    func gradientStart(_ feature: NT_Feature) -> Color {
        feature.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given feature if applicable:
    func gradientEnd(_ feature: NT_Feature) -> Color {
        feature.gradientEnd
    }
    
    /// Returns the icon of the given feature:
    func icon(_ feature: NT_Feature) -> String {
        feature.icon
    }
    
    /// Returns the scale effect of the content in the given phase (Needed to add the scroll transition when scrolling between the different features):
    nonisolated func scaleEffect(inPhase phase: ScrollTransitionPhase) -> Double {
        phase.isIdentity ? 1 : 0.8
    }
    
    /// Lets the user sign up for the account in the app:
    func signUp() {
        
        /// Dismissing the view:
        dismiss()
        
        /*
         
         NOTE: You can add your own logic for signing up here.
         
         */
        
    }
    
    /// Lets the user login into their account in the app:
    func login() {
        
        /// Dismissing the view:
        dismiss()
        
        /*
         
         NOTE: You can add your own logic for logging in here.
         
         */
        
    }
}
