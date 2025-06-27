//
//  SortAndFilterThree+FunctionsExtension.swift
//  Native
//

import Foundation

extension SortAndFilterThreeView {
    
    // MARK: - Functions:
    
    /// Clears all of the filters that are currently selected:
    func clearAll() {
        
        /*
         
         NOTE: You can add your own logic for clearing all of the filters here.
         
         */
        
    }
    
    /// Applies all of the filters that are currently selected:
    func apply() {
        
        /*
         
         NOTE: You can add your own logic for applying all of the filters here.
         
         */
        
    }
    
    /// Method that gets called whenever the time period filter changes:
    func timePeriodFilterOnChange(
        _ previousFilter: NT_BudgetTimePeriodFilter,
        _ newFilter: NT_BudgetTimePeriodFilter
    ) {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
