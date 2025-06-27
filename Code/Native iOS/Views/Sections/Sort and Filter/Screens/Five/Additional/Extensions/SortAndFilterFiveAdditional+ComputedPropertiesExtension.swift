//
//  SortAndFilterFiveAdditional+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension SortAndFilterFiveAdditionalView {
    
    // MARK: - Computed properties:
    
    /// An array of the type filters to select from:
    var typeFilters: [NT_AdditionalTypeFilter] {
        NT_AdditionalTypeFilter.allCases
    }
    
    /// An array of the color filters to select from:
    var colorFilters: [NT_ProductColorFilter] {
        NT_ProductColorFilter.allCases
    }
    
    /// An array of the customization options filters to select from:
    var customizationOptionsFilters: [NT_AdditionalCustomizationOptionsFilter] {
        NT_AdditionalCustomizationOptionsFilter.allCases
    }
    
    /// Range of the size filter stepper:
    var sizeRange: ClosedRange<Int> {
        1...1000
    }
    
    /// Title of the type filter picker:
    var typeFilterPickerTitle: LocalizedStringKey {
        "Type"
    }
    
    /// Title of the 'Reviews' item:
    var reviewsTitle: String {
        "Reviews"
    }
}
