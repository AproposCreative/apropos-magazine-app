//
//  PaywallThreePlans+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension PaywallThreePlansView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the pro plans to select from is empty:
    var isEmpty: Bool {
        plans.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Starting color of the background of the view:
    var backgroundGradientStart: Color {
        .blueGradientStart.opacity(backgroundOpacity)
    }
    
    /// Ending color of the background of the view:
    var backgroundGradientEnd: Color {
        .blueGradientEnd.opacity(backgroundOpacity)
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    // MARK: - Private computed properties:
    
    /// Opacity of the background of the view:
    private var backgroundOpacity: Double {
        colorScheme == .dark ? 0.16 : 0.08
    }
}
