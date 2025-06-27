//
//  PasswordResetTwo+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PasswordResetTwoView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Update Password' button should be disabled:
    var isUpdatePasswordDisabled: Bool {
        emailAddress.isEmpty
        || newPassword.isEmpty
        || confirmedNewPassword != newPassword
    }
}
