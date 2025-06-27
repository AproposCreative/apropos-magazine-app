//
//  ProductDetailsTwoToolbar+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProductDetailsTwoToolbarView {
    
    // MARK: - Computed properties:
    
    /// An array of the configuration options of the product to display:
    var configurations: [NT_ProductConfiguration] {
        product.configurations
    }
    
    /// 'Bool' value indicating whether or not the configuration options of the product should be shown at all:
    var isShowingConfigurations: Bool {
        !configurations.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the 'Buy' button should be disabled:
    var isBuyDisabled: Bool {
        selectedConfiguration == nil
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
