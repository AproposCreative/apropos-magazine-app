//
//  LoginFive+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension LoginFiveView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Login' button should be disabled:
    var isLoginDisabled: Bool {
        emailAddress.isEmpty
        || password.isEmpty
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
}
