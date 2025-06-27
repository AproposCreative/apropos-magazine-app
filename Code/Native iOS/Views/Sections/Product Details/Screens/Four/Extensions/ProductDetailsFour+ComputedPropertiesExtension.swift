//
//  ProductDetailsFour+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension ProductDetailsFourView {
    
    // MARK: - Computed properties:
    
    /// Title of the product to display the details for:
    var title: String {
        product.title
    }
    
    /// Blurb of the product to display the details for:
    var blurb: String {
        product.blurb
    }
    
    /// Price of the product to display the details for as a string:
    var price: String {
        product.price.formatted(.currency(code: "USD"))
    }
    
    /// Thumbnail image of the product to display the details for:
    var thumbnailImage: Image {
        .init(product.largeThumbnailImage)
    }
    
    /// Height of the thumbnail image that is based on the size of the dynamic type that is currently selected:
    var thumbnailImageHeight: Double {
        dynamicTypeSize >= .accessibility1 ? 600 : 400
    }
}
