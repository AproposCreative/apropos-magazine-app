//
//  SortAndFilterSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension SortAndFilterSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_SortAndFilterScreen] {
        NT_SortAndFilterScreen.allCases
    }
}
