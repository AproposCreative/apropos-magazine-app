//
//  ProductDetailsThreeToolbar+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProductDetailsThreeToolbarView {
    
    // MARK: - Computed properties:
    
    /// An array of the color options of the product to display:
    var colors: [NT_Color] {
        product.colors
    }
    
    /// 'Bool' value indicating whether or not the color options of the product should be shown at all:
    var isShowingColors: Bool {
        !colors.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the 'Buy' button should be disabled:
    var isBuyDisabled: Bool {
        selectedColor == nil
    }
}
