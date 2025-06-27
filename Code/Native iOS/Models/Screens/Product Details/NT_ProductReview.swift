//
//  NT_ProductReview.swift
//  Native
//

import Foundation

struct NT_ProductReview {
    
    // MARK: - Properties:
    
    /// Identifier of the review:
    let id: String
    
    /// Title of the review:
    let title: String
    
    /// Content of the review:
    let content: String
    
    /// Number of the stars that the user has given in their review:
    let rating: Int
    
    /// Image of the person who left the review:
    let image: String
    
    init(
        id: String,
        title: String,
        content: String,
        rating: Int,
        image: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.content = content
        self.rating = rating
        self.image = image
    }
}

// MARK: - Identifiable:

extension NT_ProductReview: Identifiable {  }

// MARK: - Equatable:

extension NT_ProductReview: Equatable {  }

// MARK: - Hashable:

extension NT_ProductReview: Hashable {  }

// MARK: - Example:

extension NT_ProductReview {
    
    // MARK: - Computed properties:
    
    /// An array of the example reviews:
    static var example: [NT_ProductReview] {
        [
            .init(
                id: "Item.1",
                title: "Truly Amazing",
                content: "I liked this product from the first sight as the quality is so amazing and it has a ton of great features too.",
                rating: 5,
                image: Images.productDetails13
            ),
            .init(
                id: "Item.2",
                title: "I am happy",
                content: "I wasn't sure if this product would suit me, but after trying it out for a few days, I can confirm it's awesome!",
                rating: 5,
                image: Images.productDetails14
            ),
            .init(
                id: "Item.3",
                title: "Loving this product!!",
                content: "Such a nice product that has everything I would ever want plus a lot more for such a low price.",
                rating: 5,
                image: Images.productDetails15
            )
        ]
    }
}
