//
//  MainSevenProducts+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainSevenProductsView {
    
    // MARK: - Functions:
    
    /// Returns the identifier of the given product:
    func identifier(_ product: NT_Product) -> String {
        product.id
    }
    
    /// Returns the title of the given product:
    func title(_ product: NT_Product) -> String {
        product.title
    }
    
    /// Returns the description of the given product:
    func shortDescription(_ product: NT_Product) -> String {
        product.shortDescription
    }
    
    /// Returns the price of the given product as a string:
    func price(_ product: NT_Product) -> String {
        product.price.formatted(.currency(code: "USD"))
    }
    
    /// Returns the small thumbnail image of the given product:
    func smallThumbnailImage(_ product: NT_Product) -> Image {
        .init(product.smallThumbnailImage)
    }
    
    /// Returns a 'Bool' value indicating whether or not the given product has the description:
    func doesHaveShortDescription(_ product: NT_Product) -> Bool {
        product.doesHaveShortDescription
    }
}
