//
//  PaywallFifteen+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallFifteenView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the pro plan is actually available for purchase:
    var isPlanAvailable: Bool {
        plan != nil
    }
    
    /// Title of the 'Purchase' button:
    var purchaseTitle: String {
        if let plan {
            return plan.price
        } else {
            return ""
        }
    }
    
    /// An actual image to display as the background of the view:
    var image: Image {
        .init(.paywall15)
    }
    
    /// Color of the overlay of the image that is displayed as the background of the view:
    var imageOverlayColor: Color {
        .black.opacity(0.48)
    }
    
    /// Color of the divider of the view:
    var dividerColor: Color {
        .white.opacity(0.3)
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
