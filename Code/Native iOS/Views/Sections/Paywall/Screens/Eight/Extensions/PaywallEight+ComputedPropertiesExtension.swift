//
//  PaywallEight+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallEightView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the pro plans to select from is empty:
    var isPlansEmpty: Bool {
        plans.isEmpty
    }
    
    /// Color of the background of the view:
    var backgroundColor: Color {
        .init(.systemGroupedBackground)
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
