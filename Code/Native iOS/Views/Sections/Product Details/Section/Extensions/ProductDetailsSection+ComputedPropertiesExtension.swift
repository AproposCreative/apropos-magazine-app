//
//  ProductDetailsSection+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProductDetailsSectionView {
    
    // MARK: - Computed properties:
    
    /// An array of the screens to display:
    var screens: [NT_ProductDetailsScreen] {
        NT_ProductDetailsScreen.allCases
    }
    
    /// Product to display the details for:
    var product: NT_Product {
        .example.first!
    }
}
