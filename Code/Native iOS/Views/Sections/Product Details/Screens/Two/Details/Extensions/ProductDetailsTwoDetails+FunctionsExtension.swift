//
//  ProductDetailsTwoDetails+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProductDetailsTwoDetailsView {
    
    // MARK: - Functions:
    
    /// Returns the content of the given image:
    func imageContent(_ image: NT_Image) -> Image {
        .init(image.content)
    }
}
