//
//  ProductDetailsTwoDetails+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProductDetailsTwoDetailsView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
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
}
