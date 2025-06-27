//
//  SortAndFilterThreeTypes+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SortAndFilterThreeTypesView {
    
    // MARK: - Computed properties:
    
    /// An array of the transaction type filters to select from:
    var transactionTypeFilters: [NT_TransactionTypeFilter] {
        NT_TransactionTypeFilter.allCases
    }
    
    /// Padding around the content of the view:
    var padding: Double {
        0
    }
}
