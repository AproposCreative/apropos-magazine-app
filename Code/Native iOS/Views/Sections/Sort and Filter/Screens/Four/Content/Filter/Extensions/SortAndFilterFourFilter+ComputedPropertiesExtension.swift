//
//  SortAndFilterFourFilter+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SortAndFilterFourFilterView {
    
    // MARK: - Computed properties:
    
    /// An array of the filters to select from:
    var filters: [NT_ProjectFilter] {
        NT_ProjectFilter.allCases
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
