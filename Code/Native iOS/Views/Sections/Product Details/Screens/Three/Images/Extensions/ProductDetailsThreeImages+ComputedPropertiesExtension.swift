//
//  ProductDetailsThreeImages+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProductDetailsThreeImagesView {
    
    // MARK: - Computed properties:
    
    /// An array of the images of the product to display:
    var images: [NT_Image] {
        product.additionalImages.map {
            .init(
                id: $0,
                content: $0,
                accessibilityLabel: $0
            )
        }
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !images.isEmpty
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
}
