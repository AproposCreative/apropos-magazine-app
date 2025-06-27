//
//  CategoryRow+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension CategoryRowView {
    
    // MARK: - Computed properties:
    
    /// Title of the category:
    var title: String {
        category.title
    }
    
    /// Icon of the category:
    var icon: String {
        category.icon
    }
}
