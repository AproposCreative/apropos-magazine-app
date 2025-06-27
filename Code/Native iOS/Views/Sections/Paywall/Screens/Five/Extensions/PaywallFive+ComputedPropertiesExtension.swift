//
//  PaywallFive+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallFiveView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the pro plan is actually available for purchase:
    var isPlanAvailable: Bool {
        plan != nil
    }
    
    /// Title of the 'Purchase' button:
    var purchaseTitle: String {
        if let plan {
            return "\(plan.priceOnly) - Get AppLayouts Pro"
        } else {
            return ""
        }
    }
    
    /// An actual image to display as the background of the view:
    var image: Image {
        .init(.paywall5)
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
