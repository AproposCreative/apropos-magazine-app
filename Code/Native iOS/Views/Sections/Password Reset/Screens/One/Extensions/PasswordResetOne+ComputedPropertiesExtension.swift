//
//  PasswordResetOne+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PasswordResetOneView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Update Password' button should be disabled:
    var isUpdatePasswordDisabled: Bool {
        emailAddress.isEmpty
        || newPassword.isEmpty
        || confirmedNewPassword != newPassword
    }
    
    /// Minimum height that the password text field should have:
    var passwordTextFieldMinHeight: Double {
        46
    }
}
