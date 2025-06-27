//
//  LoginTwo+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension LoginTwoView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Login' button should be disabled:
    var isLoginDisabled: Bool {
        emailAddress.isEmpty
        || password.isEmpty
    }
}
