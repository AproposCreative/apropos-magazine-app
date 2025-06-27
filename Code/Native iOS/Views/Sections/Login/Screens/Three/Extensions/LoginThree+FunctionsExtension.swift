//
//  LoginThree+FunctionsExtension.swift
//  Native
//

import Foundation

extension LoginThreeView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given type of the account:
    func title(_ type: NT_AccountType) -> String {
        type.title
    }
    
    /// Lets the user login into their account in the app:
    func login() {
        
        /// Dismissing the view:
        dismiss()
        
        /*
         
         NOTE: You can add your own logic for logging in here.
         
         */
        
    }
    
    /// Lets the user reset the password of their account in the app.
    func resetPassword() {
        
        /// Dismissing the view:
        dismiss()
        
        /*
         
         NOTE: You can add your own logic for resetting the password here.
         
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
    
    /// Method that gets called whenever the account type changes:
    func accountTypeOnChange(
        _ previousType: NT_AccountType,
        _ newType: NT_AccountType
    ) {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
