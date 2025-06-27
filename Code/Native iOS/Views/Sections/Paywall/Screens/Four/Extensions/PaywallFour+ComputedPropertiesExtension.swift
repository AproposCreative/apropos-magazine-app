//
//  PaywallFour+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallFourView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the pro plans to select from is empty:
    var isPlansEmpty: Bool {
        plans.isEmpty
    }
    
    /// An actual image to display:
    var image: Image {
        .init(.paywall4)
    }
    
    /// Starting color of the gradient of the background of the image that is displayed:
    var imageBackgroundGradientStart: Color {
        .blueGradientStart.opacity(imageBackgroundOpacity)
    }
    
    /// Ending color of the gradient of the background of the image that is displayed:
    var imageBackgroundGradientEnd: Color {
        .blueGradientEnd.opacity(imageBackgroundOpacity)
    }
    
    // MARK: - Private computed properties:
    
    /// Opacity of the background of the image that is displayed:
    private var imageBackgroundOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.12
    }
}
