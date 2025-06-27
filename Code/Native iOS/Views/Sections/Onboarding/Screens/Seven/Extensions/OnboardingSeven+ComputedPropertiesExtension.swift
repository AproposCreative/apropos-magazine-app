//
//  OnboardingSeven+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension OnboardingSevenView {
    
    // MARK: - Computed properties:
    
    /// An actual image to display as the background of the view:
    var image: Image {
        .init(.onboarding7)
    }
    
    /// Color of the overlay of the image that is displayed as the background of the view:
    var imageOverlayColor: Color {
        .black.opacity(0.48)
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
