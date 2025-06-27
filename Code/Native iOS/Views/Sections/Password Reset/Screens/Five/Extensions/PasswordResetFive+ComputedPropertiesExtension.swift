//
//  PasswordResetFive+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PasswordResetFiveView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Update Password' button should be disabled:
    var isUpdatePasswordDisabled: Bool {
        emailAddress.isEmpty
        || newPassword.isEmpty
        || confirmedNewPassword != newPassword
    }
}
