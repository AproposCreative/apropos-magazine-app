//
//  SortAndFilterThreeCategories+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension SortAndFilterThreeCategoriesView {
    
    // MARK: - Functions:
    
    /// Returns a 'Bool' value indicating whether or not the given budget category filter is currently selected:
    func isSelected(_ filter: NT_BudgetCategoryFilter) -> Bool {
        selectedBudgetCategoryFilters.contains(filter)
    }
    
    /// Returns the title of the given budget category filter:
    func title(_ filter: NT_BudgetCategoryFilter) -> String {
        filter.title
    }
    
    /// Returns the color of the given budget category filter:
    func color(_ filter: NT_BudgetCategoryFilter) -> Color {
        filter.color
    }
    
    /// Returns the starting color of the gradient of the given budget category filter:
    func gradientStart(_ filter: NT_BudgetCategoryFilter) -> Color {
        filter.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given budget category filter:
    func gradientEnd(_ filter: NT_BudgetCategoryFilter) -> Color {
        filter.gradientEnd
    }
    
    /// Returns the icon of the given budget category filter:
    func icon(_ filter: NT_BudgetCategoryFilter) -> String {
        filter.icon
    }
    
    /// Returns the width of the border of the given budget category filter that is based on whether or not it's currently selected:
    func borderWidth(_ filter: NT_BudgetCategoryFilter) -> Double {
        isSelected(filter) ? 2 : 1
    }
    
    /// Returns the accessibility traits of the given filter to indicate that it's an actual button, as well as whether or not it's currently selected:
    func accessibilityTraits(_ filter: NT_BudgetCategoryFilter) -> AccessibilityTraits {
        isSelected(filter) ? [.isButton, .isSelected] : [.isButton]
    }
    
    /// Selects or deselects the given budget category filter:
    func select(_ filter: NT_BudgetCategoryFilter) {
        
        /// Firstly checking whether or not the given budget category filter is already selected:
        if isSelected(filter) {
            
            /// If yes, then also making sure that we can get the index of the given budget category filter in an array of the budget category filters that are currently selected:
            guard let index: Int = selectedBudgetCategoryFilters.firstIndex(of: filter) else { return }
            
            /// If yes, then deselecting the given budget category filter by removing it from an array of the budget category filters that are currently selected based on its index:
            selectedBudgetCategoryFilters.remove(at: index)
        } else {
            
            /// If not, then simply appending the given budget category filter into an array of the budget category filters that are currently selected:
            selectedBudgetCategoryFilters.append(filter)
        }
        
        /// Lastly triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
