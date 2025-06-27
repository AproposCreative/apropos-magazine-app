//
//  PasswordResetThree+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PasswordResetThreeView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Update Password' button should be disabled:
    var isUpdatePasswordDisabled: Bool {
        emailAddress.isEmpty
        || newPassword.isEmpty
        || confirmedNewPassword != newPassword
    }
    
    /// An actual image to display as the background of the view:
    var image: Image {
        .init(.passwordReset3)
    }
    
    /// Color of the background of each of the text fields:
    var textFieldBackground: Color {
        .init(.systemFill)
    }
    
    /// Minimum height that the password text field should have:
    var passwordTextFieldMinHeight: Double {
        46
    }
}
