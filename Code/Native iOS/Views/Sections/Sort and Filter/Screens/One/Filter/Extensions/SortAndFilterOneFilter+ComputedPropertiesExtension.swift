//
//  SortAndFilterOneFilter+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SortAndFilterOneFilterView {
    
    // MARK: - Computed properties:
    
    /// An array of the category filters to select from:
    var categoryFilters: [NT_ProductCategoryFilter] {
        NT_ProductCategoryFilter.allCases
    }
    
    /// An array of the brand filters to select from:
    var brandFilters: [NT_ProductBrandFilter] {
        NT_ProductBrandFilter.allCases
    }
    
    /// An array of the processor filters to select from:
    var processorFilters: [NT_ProductProcessorFilter] {
        NT_ProductProcessorFilter.allCases
    }
    
    /// An array of the RAM filters to select from:
    var ramFilters: [NT_ProductRAMFilter] {
        NT_ProductRAMFilter.allCases
    }
    
    /// An array of the storage filters to select from:
    var storageFilters: [NT_ProductStorageFilter] {
        NT_ProductStorageFilter.allCases
    }
    
    /// An array of the color filters to select from:
    var colorFilters: [NT_ProductColorFilter] {
        NT_ProductColorFilter.allCases
    }
}
