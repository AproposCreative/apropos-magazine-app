//
//  OnboardingTwo+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension OnboardingTwoView {
    
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
        .init(feature.onboarding2Image)
    }
    
    /// Returns the alignment of the image of the given feature:
    func imageAlignment(_ feature: NT_Feature) -> Alignment {
        feature.imageAlignment
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
