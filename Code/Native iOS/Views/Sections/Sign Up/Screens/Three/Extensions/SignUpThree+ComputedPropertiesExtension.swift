//
//  SignUpThree+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SignUpThreeView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Create Account' button should be disabled:
    var isCreateAccountDisabled: Bool {
        emailAddress.isEmpty
        || username.isEmpty
        || password.isEmpty
        || confirmedPassword != password
        || firstName.isEmpty
        || lastName.isEmpty
        || streetName.isEmpty
        || city.isEmpty
        || zipCode.isEmpty
    }
    
    /// Link to the page with the terms of service of the app (You can replace it with your own link):
    var termsOfServiceLink: URL {
        Links.termsOfService
    }
    
    /// Minimum height that the password text field should have:
    var passwordTextFieldMinHeight: Double {
        46
    }
}
