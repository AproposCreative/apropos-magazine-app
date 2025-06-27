//
//  PaywallTwelve+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallTwelveView {
    
    // MARK: - Computed properties:
    
    /// An array of the main features to display:
    var mainFeatures: [NT_Feature] {
        .init(NT_Feature.allCases.prefix(3))
    }
    
    /// 'Bool' value indicating whether or not an array of the pro plans to select from is empty:
    var isPlansEmpty: Bool {
        plans.isEmpty
    }
    
    /// Color of the background of the view:
    var backgroundColor: Color {
        .init(.systemGroupedBackground)
    }
}
