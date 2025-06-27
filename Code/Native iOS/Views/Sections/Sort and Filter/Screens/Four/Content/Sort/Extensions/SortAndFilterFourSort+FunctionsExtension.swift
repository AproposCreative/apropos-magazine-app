//
//  SortAndFilterFourSort+FunctionsExtension.swift
//  Native
//

import Foundation

extension SortAndFilterFourSortView {
    
    // MARK: - Functions:
    
    /// Returns a 'Bool' value indicating whether or not the given sort order is currently selected:
    func isSelected(_ sortOrder: NT_ProjectSortOrder) -> Bool {
        selectedSortOrder == sortOrder
    }
    
    /// Returns the title of the given sort order:
    func title(_ sortOrder: NT_ProjectSortOrder) -> String {
        sortOrder.title
    }
    
    /// Selects the given sort order unless it's already selected:
    func select(_ sortOrder: NT_ProjectSortOrder) {
        
        /// Firstly making sure that the given sort order isn't already selected:
        if !isSelected(sortOrder) {
            
            /// If yes, then selecting the given sort order by updating the 'selectedSortOrder' property with the given sort order:
            selectedSortOrder = sortOrder
            
            /// Lastly triggering the selection changed haptic feedback indicating that there was a change:
            HapticFeedbacks.selectionChanged()
        }
    }
}
