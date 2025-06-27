//
//  SignUpTwo+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SignUpTwoView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Create Account' button should be disabled:
    var isCreateAccountDisabled: Bool {
        emailAddress.isEmpty
        || password.isEmpty
        || confirmedPassword != password
    }
    
    /// Link to the page with the terms of service of the app (You can replace it with your own link):
    var termsOfServiceLink: URL {
        Links.termsOfService
    }
}
