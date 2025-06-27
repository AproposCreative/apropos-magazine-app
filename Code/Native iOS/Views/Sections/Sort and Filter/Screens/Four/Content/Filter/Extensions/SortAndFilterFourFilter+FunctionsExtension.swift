//
//  SortAndFilterFourFilter+FunctionsExtension.swift
//  Native
//

import Foundation

extension SortAndFilterFourFilterView {
    
    // MARK: - Functions:
    
    /// Returns a 'Bool' value indicating whether or not the given filter is currently selected:
    func isSelected(_ filter: NT_ProjectFilter) -> Bool {
        selectedFilters.contains(filter)
    }
    
    /// Returns the title of the given filter:
    func title(_ filter: NT_ProjectFilter) -> String {
        filter.title
    }
    
    /// Returns the description of the given filter:
    func description(_ filter: NT_ProjectFilter) -> String {
        filter.description
    }
    
    /// Selects or deselects the given filter:
    func select(_ filter: NT_ProjectFilter) {
        
        /// Firstly checking whether or not the given filter is already selected:
        if isSelected(filter) {
            
            /// If yes, then also making sure that we can get the index of the given filter in an array of the filters that are currently selected:
            guard let index: Int = selectedFilters.firstIndex(of: filter) else { return }
            
            /// If yes, then deselecting the given filter by removing it from an array of the filters that are currently selected based on its index:
            selectedFilters.remove(at: index)
        } else {
            
            /// If not, then simply appending the given filter into an array of the filters that are currently selected:
            selectedFilters.append(filter)
        }
        
        /// Lastly triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
