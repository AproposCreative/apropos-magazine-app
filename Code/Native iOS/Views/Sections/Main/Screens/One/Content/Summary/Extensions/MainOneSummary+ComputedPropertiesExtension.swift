//
//  MainOneSummary+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainOneSummaryView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !bars.isEmpty
    }
    
    /// An array of the time periods to select from:
    var timePeriods: [NT_TransactionsTimePeriod] {
        NT_TransactionsTimePeriod.allCases
    }
}
