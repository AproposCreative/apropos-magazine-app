//
//  SortAndFilterOneFilter+FunctionsExtension.swift
//  Native
//

import Foundation

extension SortAndFilterOneFilterView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given category filter:
    func title(_ filter: NT_ProductCategoryFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given brand filter:
    func title(_ filter: NT_ProductBrandFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given processor filter:
    func title(_ filter: NT_ProductProcessorFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given RAM filter:
    func title(_ filter: NT_ProductRAMFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given storage filter:
    func title(_ filter: NT_ProductStorageFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given color filter:
    func title(_ filter: NT_ProductColorFilter) -> String {
        filter.title
    }
}
