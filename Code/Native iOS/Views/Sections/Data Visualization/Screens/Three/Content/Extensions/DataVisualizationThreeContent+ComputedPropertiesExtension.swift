//
//  DataVisualizationThreeContent+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension DataVisualizationThreeContentView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the categories with the income, an array of the unpaid invoices, an array of the investments, as well as an array of the categories with the expenses to display are all empty:
    var isEmpty: Bool {
        incomeCategories.isEmpty
        && unpaidInvoices.isEmpty
        && investments.isEmpty
        && expenseCategories.isEmpty
    }
    
    /// An array of the time periods to select from:
    var timePeriods: [NT_OverviewTimePeriod] {
        NT_OverviewTimePeriod.allCases
    }
}
