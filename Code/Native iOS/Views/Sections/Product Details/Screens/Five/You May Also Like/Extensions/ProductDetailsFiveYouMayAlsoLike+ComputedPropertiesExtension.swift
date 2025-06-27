//
//  ProductDetailsFiveYouMayAlsoLike+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension ProductDetailsFiveYouMayAlsoLikeView {
    
    // MARK: - Computed properties:
    
    /// An array of the products to display:
    var products: [NT_Product] {
        NT_Product.example.filter { product.similarProducts.contains($0.id) }
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !products.isEmpty
    }
    
    /// Color of the background of the view:
    var backgroundColor: Color {
        .init(.secondarySystemBackground)
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Height of each of the thumbnail images of the products that is based on the size of the dynamic type that is currently selected:
    var thumbnailImageHeight: Double {
        dynamicTypeSize >= .accessibility1 ? 224 : 168
    }
}
