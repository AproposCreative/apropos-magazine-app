//
//  SortAndFilterThreeTimePeriod+FunctionsExtension.swift
//  Native
//

import Foundation

extension SortAndFilterThreeTimePeriodView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given time period filter:
    func title(_ filter: NT_BudgetTimePeriodFilter) -> String {
        filter.title
    }
}
