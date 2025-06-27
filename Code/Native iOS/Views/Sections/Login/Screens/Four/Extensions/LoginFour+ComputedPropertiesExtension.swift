//
//  LoginFour+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension LoginFourView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the 'Login' button should be disabled:
    var isLoginDisabled: Bool {
        emailAddress.isEmpty
        || password.isEmpty
    }
    
    /// An actual image to display as the background of the view:
    var image: Image {
        .init(.login4)
    }
    
    /// Color of the overlay of the image that is displayed as the background of the view:
    var imageOverlayColor: Color {
        .black.opacity(0.48)
    }
    
    /// Color of the background of the view:
    var backgroundColor: Color {
        .init(.systemFill)
    }
    
    /// Color of the buttons that are placed in the toolbar:
    var toolbarButtonColor: Color {
        .primary
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
