//
//  PaywallTwo+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallTwoView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the pro plans to select from is empty:
    var isPlansEmpty: Bool {
        plans.isEmpty
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
    
    /// Opacity of the background of the button of each of the pro plans that isn't monthly:
    var nonMonthlyPlanButtonBackgroundOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.12
    }
}
