//
//  SortAndFilterThreeTimePeriod+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SortAndFilterThreeTimePeriodView {
    
    // MARK: - Computed properties:
    
    /// An array of the time period filters to select from:
    var timePeriodFilters: [NT_BudgetTimePeriodFilter] {
        NT_BudgetTimePeriodFilter.allCases
    }
}
