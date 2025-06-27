//
//  OnboardingTen+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension OnboardingTenView {
    
    // MARK: - Computed properties:
    
    /// Link to the page with the terms of service of the app (You can replace it with your own link):
    var termsOfServiceLink: URL {
        Links.termsOfService
    }
    
    /// An actual image to display as the background of the view:
    var image: Image {
        .init(.onboarding10)
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
