//
//  SortAndFilterThreeTypes+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension SortAndFilterThreeTypesView {
    
    // MARK: - Functions:
    
    /// Returns a 'Bool' value indicating whether or not the given transaction type filter is currently selected:
    func isSelected(_ filter: NT_TransactionTypeFilter) -> Bool {
        selectedTransactionTypeFilters.contains(filter)
    }
    
    /// Returns the title of the given transaction type filter:
    func title(_ filter: NT_TransactionTypeFilter) -> String {
        filter.title
    }
    
    /// Returns the width of the border of the given transaction type filter that is based on whether or not it's currently selected:
    func borderWidth(_ filter: NT_TransactionTypeFilter) -> Double {
        isSelected(filter) ? 2 : 1
    }
    
    /// Returns the size of the badge of the given transaction type filter:
    func size(_ filter: NT_TransactionTypeFilter) -> NT_BadgeSize {
        .custom(
            iconFont: .system(
                size: 13,
                weight: .semibold,
                design: .default
            ),
            iconFrame: 16,
            titleFont: .footnote.weight(.bold),
            spacing: 5,
            verticalPadding: 5,
            horizontalPadding: 10,
            borderWidth: borderWidth(filter),
            cornerRadius: 10,
            cornerStyle: .continuous
        )
    }
    
    /// Returns the accessibility traits of the given filter to indicate that it's an actual button, as well as whether or not it's currently selected:
    func accessibilityTraits(_ filter: NT_TransactionTypeFilter) -> AccessibilityTraits {
        isSelected(filter) ? [.isButton, .isSelected] : [.isButton]
    }
    
    /// Selects or deselects the given transaction type filter:
    func select(_ filter: NT_TransactionTypeFilter) {
        
        /// Firstly checking whether or not the given transaction type filter is already selected:
        if isSelected(filter) {
            
            /// If yes, then also making sure that we can get the index of the given transaction type filter in an array of the transaction type filters that are currently selected:
            guard let index: Int = selectedTransactionTypeFilters.firstIndex(of: filter) else { return }
            
            /// If yes, then deselecting the given transaction type filter by removing it from an array of the transaction type filters that are currently selected based on its index:
            selectedTransactionTypeFilters.remove(at: index)
        } else {
            
            /// If not, then simply appending the given transaction type filter into an array of the transaction type filters that are currently selected:
            selectedTransactionTypeFilters.append(filter)
        }
        
        /// Lastly triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
