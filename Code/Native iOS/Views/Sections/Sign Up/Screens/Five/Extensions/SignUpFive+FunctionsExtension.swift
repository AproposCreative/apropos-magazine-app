//
//  SignUpFive+FunctionsExtension.swift
//  Native
//

import Foundation

extension SignUpFiveView {
    
    // MARK: - Functions:
    
    /// Agrees to the terms of service and the privacy policy:
    func agreeToTermsOfServiceAndPrivacyPolicy() {
        
        /// Firstly toggling the 'isAgreedToTermsOfServiceAndPrivacyPolicy' property to agree with the terms of service and the privacy policy:
        isAgreedToTermsOfServiceAndPrivacyPolicy.toggle()
        
        /// Then triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
    
    /// Creates the account for the user in the app:
    func createAccount() {
        
        /// Dismissing the view:
        dismiss()
        
        /*
         
         NOTE: You can add your own logic for creating an account here.
         
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
