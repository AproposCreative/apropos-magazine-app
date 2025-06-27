//
//  OnboardingFourteen+FunctionsExtension.swift
//  Native
//

import Foundation

extension OnboardingFourteenView {
    
    // MARK: - Functions:
    
    /// Returns the subtitle of the given feature:
    func subtitle(_ feature: NT_Feature) -> String {
        feature.subtitle
    }
    
    /// Lets the user sign up for the account in the app:
    func signUp() {
        
        /// Dismissing the view:
        dismiss()
        
        /*
         
         NOTE: You can add your own logic for signing up here.
         
         */
        
    }
}
