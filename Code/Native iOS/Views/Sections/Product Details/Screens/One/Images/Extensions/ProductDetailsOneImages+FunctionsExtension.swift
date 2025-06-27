//
//  ProductDetailsOneImages+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProductDetailsOneImagesView {
    
    // MARK: - Functions:
    
    /// Returns the content of the given image:
    func imageContent(_ image: NT_Image) -> Image {
        .init(image.content)
    }
    
    /// Returns the accessibility label of the given image:
    func accessibilityLabel(_ image: NT_Image) -> String {
        image.accessibilityLabel
    }
}
