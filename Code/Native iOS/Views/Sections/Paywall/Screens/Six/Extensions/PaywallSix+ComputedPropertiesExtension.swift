//
//  PaywallSix+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallSixView {
    
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
    
    /// Color of the background of the view:
    var backgroundColor: Color {
        .init(.systemGroupedBackground)
    }
}
