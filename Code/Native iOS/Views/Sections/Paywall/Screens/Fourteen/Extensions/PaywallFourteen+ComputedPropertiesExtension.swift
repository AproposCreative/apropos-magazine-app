//
//  PaywallFourteen+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallFourteenView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the pro plan is actually available for purchase:
    var isPlanAvailable: Bool {
        plan != nil
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Title of the option of enable the free trial of the pro plan:
    var enableFreeTrialTitle: String {
        "30-Day Free Trial"
    }
    
    /// Title of the 'Purchase' button:
    var purchaseTitle: String {
        if let plan {
            return isFreeTrialEnabled ? "Start My Free Trial" : plan.price
        } else {
            return ""
        }
    }
    
    /// An actual image to display:
    var image: Image {
        .init(.paywall14)
    }
    
    /// Spacing between the content of the 'Enable Free Trial' option:
    var enableFreeTrialSpacing: Double {
        12
    }
}
