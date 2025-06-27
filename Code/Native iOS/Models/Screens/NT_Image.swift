//
//  NT_Image.swift
//  Native
//

import Foundation

struct NT_Image {
    
    // MARK: - Properties:
    
    /// Identifier of the image:
    let id: String
    
    /// An actual content of the image to display:
    let content: String
    
    /// Accessibility label of the image:
    let accessibilityLabel: String
    
    init(
        id: String,
        content: String,
        accessibilityLabel: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.content = content
        self.accessibilityLabel = accessibilityLabel
    }
}

// MARK: - Identifiable:

extension NT_Image: Identifiable {  }

// MARK: - Equatable:

extension NT_Image: Equatable {  }

// MARK: - Hashable:

extension NT_Image: Hashable {  }

// MARK: - Example:

extension NT_Image {
    
    // MARK: - Computed properties:
    
    /// An array of the example images:
    static var example: [NT_Image] {
        [
            .init(
                id: "Item.1",
                content: Images.productDetails2,
                accessibilityLabel: "Product image 1"
            ),
            .init(
                id: "Item.2",
                content: Images.productDetails3,
                accessibilityLabel: "Product image 2"
            ),
            .init(
                id: "Item.3",
                content: Images.productDetails4,
                accessibilityLabel: "Product image 3"
            )
        ]
    }
}
