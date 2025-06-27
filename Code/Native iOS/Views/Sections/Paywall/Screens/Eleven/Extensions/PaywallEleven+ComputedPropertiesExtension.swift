//
//  PaywallEleven+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallElevenView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the pro plans to select from is empty:
    var isPlansEmpty: Bool {
        plans.isEmpty
    }
    
    /// An actual image to display:
    var image: Image {
        .init(.paywall111)
    }
    
    /// Primary color of the view:
    var primaryColor: Color {
        .white
    }
    
    /// Secondary color of the view:
    var secondaryColor: Color {
        primaryColor.opacity(0.8)
    }
    
    /// Color of each of the dividers of the view:
    var dividerColor: Color {
        primaryColor.opacity(0.3)
    }
    
    /// Gradient of the background of the view:
    var backgroundGradient: LinearGradient {
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
