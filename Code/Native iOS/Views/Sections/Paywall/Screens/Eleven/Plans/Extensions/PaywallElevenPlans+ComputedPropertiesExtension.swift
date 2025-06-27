//
//  PaywallElevenPlans+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallElevenPlansView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the pro plans to select from is empty:
    var isEmpty: Bool {
        plans.isEmpty
    }
    
    /// Color of the view:
    var color: Color {
        .white
    }
}
