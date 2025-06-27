//
//  SortAndFilterFivePrice+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension SortAndFilterFivePriceView {
    
    // MARK: - Computed properties:
    
    /// Font of the icon of the slider for the price filter:
    var priceFilterSliderIconFont: Font {
        .system(
            size: 17,
            weight: .semibold,
            design: .default
        )
    }
    
    /// Range of the price filter slider:
    var priceRange: ClosedRange<Double> {
        0.0...1000.00
    }
    
    /// Size of the frame of the label of the price filter slider:
    var priceFilterSliderLabelFrame: Double {
        28
    }
}
