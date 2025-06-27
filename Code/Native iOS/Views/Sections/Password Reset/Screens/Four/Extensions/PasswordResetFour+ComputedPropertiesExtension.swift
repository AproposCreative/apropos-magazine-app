//
//  PasswordResetFour+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PasswordResetFourView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Update Password' button should be disabled:
    var isUpdatePasswordDisabled: Bool {
        emailAddress.isEmpty
        || newPassword.isEmpty
        || confirmedNewPassword != newPassword
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        32
    }
    
    /// Spacing between the content of the 'New Password' section:
    var newPasswordSpacing: Double {
        16
    }
    
    /// Minimum height that the password text field should have:
    var passwordTextFieldMinHeight: Double {
        46
    }
}
