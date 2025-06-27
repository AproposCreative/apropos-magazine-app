//
//  MainOneSummary+FunctionsExtension.swift
//  Native
//

import Foundation

extension MainOneSummaryView {
    
    // MARK: - Functions:
    
    /// Returns the short title of the given time period:
    func shortTitle(_ timePeriod: NT_TransactionsTimePeriod) -> String {
        timePeriod.shortTitle
    }
    
    /// Method that gets called whenever the time period changes:
    func timePeriodOnChange(
        _ previousTimePeriod: NT_TransactionsTimePeriod,
        _ newTimePeriod: NT_TransactionsTimePeriod
    ) {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
