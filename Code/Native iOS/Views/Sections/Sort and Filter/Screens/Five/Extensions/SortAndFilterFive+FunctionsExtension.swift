//
//  SortAndFilterFive+FunctionsExtension.swift
//  Native
//

import Foundation

extension SortAndFilterFiveView {
    
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
    
    /// Triggers the haptic feedback:
    func triggerHapticFeedback() {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
