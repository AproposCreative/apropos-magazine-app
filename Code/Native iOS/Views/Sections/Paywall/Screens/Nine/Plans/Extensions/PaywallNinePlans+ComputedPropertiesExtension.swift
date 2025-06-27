//
//  PaywallNinePlans+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PaywallNinePlansView {
    
    // MARK: - Computed properties:
    
    /// An array of the levels of the pro plan to display:
    var levels: [NT_ProPlanLevel] {
        NT_ProPlanLevel.allCases
    }
    
    /// 'Bool' value indicating whether or not an array of the pro plans to select from is empty:
    var isEmpty: Bool {
        plans.isEmpty
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
