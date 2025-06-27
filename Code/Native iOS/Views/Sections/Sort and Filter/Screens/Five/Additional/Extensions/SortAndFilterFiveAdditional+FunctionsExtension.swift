//
//  SortAndFilterFiveAdditional+FunctionsExtension.swift
//  Native
//

import Foundation

extension SortAndFilterFiveAdditionalView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given type filter:
    func title(_ filter: NT_AdditionalTypeFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given color filter:
    func title(_ filter: NT_ProductColorFilter) -> String {
        filter.title
    }
    
    /// Returns the title of the given customization options filter:
    func title(_ filter: NT_AdditionalCustomizationOptionsFilter) -> String {
        filter.title
    }
}
