//
//  OnboardingTen+FunctionsExtension.swift
//  Native
//

import Foundation
import AuthenticationServices

extension OnboardingTenView {
    
    // MARK: - Functions:
    
    /// Method that gets called when the authorization using the 'Continue with Apple' button is being requested:
    func onRequestContinueWithApple(_ request: ASAuthorizationAppleIDRequest) {
        
        /*
         
         NOTE: You can add your own logic for when the authorization is being requested here.
         
         */
        
    }
    
    /// Method that gets called when the authorization using the 'Continue with Apple' button was completed:
    func onCompletionContinueWithApple(_ result: Result<ASAuthorization, any Error>) {
        
        /// Dismissing the view:
        dismiss()
        
        /*
         
         NOTE: You can add your own logic for when the authorization was completed here.
         
         */
        
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
