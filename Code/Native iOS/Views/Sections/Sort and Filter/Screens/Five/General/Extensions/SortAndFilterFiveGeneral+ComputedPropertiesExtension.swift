//
//  SortAndFilterFiveGeneral+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SortAndFilterFiveGeneralView {
    
    // MARK: - Computed properties:
    
    /// An array of the category filters to select from:
    var categoryFilters: [NT_ProductCategoryFilter] {
        NT_ProductCategoryFilter.allCases
    }
    
    /// An array of the brand filters to select from:
    var brandFilters: [NT_ProductBrandFilter] {
        NT_ProductBrandFilter.allCases
    }
}
