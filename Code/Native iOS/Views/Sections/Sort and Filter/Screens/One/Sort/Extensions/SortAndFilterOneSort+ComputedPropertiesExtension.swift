//
//  SortAndFilterOneSort+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SortAndFilterOneSortView {
    
    // MARK: - Computed properties:
    
    /// An array of the sort orders to select from:
    var sortOrders: [NT_ProductSortOrder] {
        NT_ProductSortOrder.allCases
    }
}
