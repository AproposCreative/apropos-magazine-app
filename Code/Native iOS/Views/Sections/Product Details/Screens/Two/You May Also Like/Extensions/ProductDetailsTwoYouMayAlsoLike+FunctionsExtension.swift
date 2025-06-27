//
//  ProductDetailsTwoYouMayAlsoLike+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProductDetailsTwoYouMayAlsoLikeView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given product:
    func title(_ product: NT_Product) -> String {
        product.title
    }
    
    /// Returns the blurb of the given product:
    func blurb(_ product: NT_Product) -> String {
        product.blurb
    }
    
    /// Returns the price of the given product as a string:
    func price(_ product: NT_Product) -> String {
        product.price.formatted(.currency(code: "USD"))
    }
    
    /// Returns the thumbnail image of the given product:
    func thumbnailImage(_ product: NT_Product) -> Image {
        .init(product.smallThumbnailImage)
    }
}
