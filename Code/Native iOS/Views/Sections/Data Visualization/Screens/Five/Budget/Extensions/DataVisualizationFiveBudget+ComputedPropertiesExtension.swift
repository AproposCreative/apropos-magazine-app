//
//  DataVisualizationFiveBudget+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension DataVisualizationFiveBudgetView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !budgets.isEmpty
    }
    
    /// Code of the currency to use for the amounts of each of the budgets:
    var currencyCode: String {
        "USD"
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Size of the frame of the icon that is displayed in the header of the view that is based on the size of the dynamic type that is currently selected:
    var headerIconFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 25
    }
}
