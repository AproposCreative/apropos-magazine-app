//
//  ProductDetailsFiveDetails+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension ProductDetailsFiveDetailsView {
    
    // MARK: - Computed properties:
    
    /// Title of the product to display the details for:
    var title: String {
        product.title
    }
    
    /// Price of the product to display the details for as a string:
    var price: String {
        product.price.formatted(.currency(code: "USD"))
    }
    
    /// Longer description of the product to display the details for:
    var longDescription: String {
        product.longDescription
    }
    
    /// Thumbnail image of the product to display:
    var thumbnailImage: Image {
        .init(product.largeThumbnailImage)
    }
    
    /// Offset of the badge of the thumbnail image on the X-axis and the Y-axis:
    var thumbnailImageBadgeOffset: Double {
        12
    }
    
    /// Height of the thumbnail image that is based on the size of the dynamic type that is currently selected:
    var thumbnailImageHeight: Double {
        dynamicTypeSize >= .accessibility1 ? 304 : 224
    }
}
