//
//  NT_ProfilePost.swift
//  Native
//

import Foundation

struct NT_ProfilePost {
    
    // MARK: - Properties:
    
    /// Identifier of the post:
    let id: String
    
    /// Image of the post:
    let image: String
    
    init(
        id: String,
        image: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.image = image
    }
}

// MARK: - Identifiable:

extension NT_ProfilePost: Identifiable {  }

// MARK: - Equatable:

extension NT_ProfilePost: Equatable {  }

// MARK: - Hashable:

extension NT_ProfilePost: Hashable {  }

// MARK: - Example:

extension NT_ProfilePost {
    
    // MARK: - Computed properties:
    
    /// An array of the example posts:
    static var example: [NT_ProfilePost] {
        [
            .init(
                id: "Item.1",
                image: Images.profile22
            ),
            .init(
                id: "Item.2",
                image: Images.profile23
            ),
            .init(
                id: "Item.3",
                image: Images.profile24
            ),
            .init(
                id: "Item.4",
                image: Images.profile25
            ),
            .init(
                id: "Item.5",
                image: Images.profile26
            ),
            .init(
                id: "Item.6",
                image: Images.profile27
            ),
            .init(
                id: "Item.7",
                image: Images.profile28
            ),
            .init(
                id: "Item.8",
                image: Images.profile29
            ),
            .init(
                id: "Item.9",
                image: Images.profile210
            ),
        ]
    }
}
