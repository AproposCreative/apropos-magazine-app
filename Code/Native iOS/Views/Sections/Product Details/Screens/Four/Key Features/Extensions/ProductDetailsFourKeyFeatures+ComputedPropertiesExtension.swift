//
//  ProductDetailsFourKeyFeatures+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProductDetailsFourKeyFeaturesView {
    
    // MARK: - Computed properties:
    
    /// An array of the key features to display:
    var keyFeatures: [NT_ProductKeyFeature] {
        product.keyFeatures
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !keyFeatures.isEmpty
    }
}
