//
//  DataVisualizationFive+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension DataVisualizationFiveView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the categories, as well as an array of the budgets to display are both empty:
    var isEmpty: Bool {
        categories.isEmpty && budgets.isEmpty
    }
    
    /// An array of the time periods to select from:
    var timePeriods: [NT_SummaryTimePeriod] {
        NT_SummaryTimePeriod.allCases
    }
}
