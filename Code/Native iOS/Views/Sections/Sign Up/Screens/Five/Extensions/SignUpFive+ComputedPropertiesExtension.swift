//
//  SignUpFive+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension SignUpFiveView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Create Account' button should be disabled:
    var isCreateAccountDisabled: Bool {
        emailAddress.isEmpty
        || password.isEmpty
        || confirmedPassword != password
        || !isAgreedToTermsOfServiceAndPrivacyPolicy
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Gradient of the title:
    var titleGradient: LinearGradient {
        .init(
            colors: [
                .blueGradientStart,
                .blueGradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Spacing between the content of the notice:
    var noticeSpacing: Double {
        8
    }
    
    /// Minimum height that the password text field should have:
    var passwordTextFieldMinHeight: Double {
        46
    }
}
