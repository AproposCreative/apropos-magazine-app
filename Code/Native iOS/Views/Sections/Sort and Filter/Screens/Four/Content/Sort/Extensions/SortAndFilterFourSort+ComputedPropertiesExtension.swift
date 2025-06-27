//
//  SortAndFilterFourSort+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SortAndFilterFourSortView {
    
    // MARK: - Computed properties:
    
    /// An array of the sort orders to select from:
    var sortOrders: [NT_ProjectSortOrder] {
        NT_ProjectSortOrder.allCases
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
