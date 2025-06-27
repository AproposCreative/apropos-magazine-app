//
//  PaywallTen+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension PaywallTenView {
    
    // MARK: - Computed properties:
    
    /// An array of the features to display:
    var features: [NT_Feature] {
        .init(NT_Feature.allCases.prefix(4))
    }
    
    /// 'Bool' value indicating whether or not an array of the pro plans to select from is empty:
    var isPlansEmpty: Bool {
        plans.isEmpty
    }
}
