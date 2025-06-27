//
//  PaywallEightPlans+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PaywallEightPlansView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the pro plans to select from is empty:
    var isEmpty: Bool {
        plans.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
