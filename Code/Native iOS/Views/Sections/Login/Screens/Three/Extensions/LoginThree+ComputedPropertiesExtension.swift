//
//  LoginThree+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension LoginThreeView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Login' button should be disabled:
    var isLoginDisabled: Bool {
        emailAddress.isEmpty
        || password.isEmpty
    }
    
    /// An array of the types of the account to select from:
    var accountTypes: [NT_AccountType] {
        NT_AccountType.allCases
    }
}
