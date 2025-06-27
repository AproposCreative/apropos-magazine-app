//
//  Categories+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension CategoriesView {
    
    // MARK: - Computed properties:
    
    /// An array of the screen categories to display:
    var categories: [NT_Category] {
        NT_Category.allCases
    }
}
