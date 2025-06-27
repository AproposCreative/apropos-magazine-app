//
//  LoginOne+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension LoginOneView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Login' button should be disabled:
    var isLoginDisabled: Bool {
        emailAddress.isEmpty
        || password.isEmpty
    }
}
