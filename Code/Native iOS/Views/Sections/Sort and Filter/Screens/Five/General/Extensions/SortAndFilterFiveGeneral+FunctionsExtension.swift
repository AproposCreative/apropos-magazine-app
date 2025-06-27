//
//  SortAndFilterFiveGeneral+FunctionsExtension.swift
//  Native
//

import Foundation

extension SortAndFilterFiveGeneralView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given category filter:
    func title(_ filter: NT_ProductCategoryFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given brand filter:
    func title(_ filter: NT_ProductBrandFilter) -> String {
        filter.title
    }
}
