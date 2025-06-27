//
//  DataVisualizationTwo+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension DataVisualizationTwoView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the usage items, as well as the performance items to display are both empty:
    var isEmpty: Bool {
        usageItems.isEmpty && performanceItems.isEmpty
    }
    
    /// Color of the background of the view:
    var backgroundColor: Color {
        .init(.systemGroupedBackground)
    }
}
