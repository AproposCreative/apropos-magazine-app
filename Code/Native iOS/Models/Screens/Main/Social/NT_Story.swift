//
//  NT_Story.swift
//  Native
//

import SwiftUI

struct NT_Story {
    
    // MARK: - Properties:
    
    /// Identifier of the story:
    let id: String
    
    /// Image of the story:
    let image: String
    
    /// Color of the story:
    let color: Color
    
    /// Starting color of the gradient of the story if applicable:
    let gradientStart: Color
    
    /// Ending color of the gradient of the story if applicable:
    let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the given story has already been seen by the user:
    let isSeen: Bool
    
    /// Account that the story was posted from:
    let account: NT_Account
    
    init(
        id: String,
        image: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        isSeen: Bool,
        account: NT_Account
    ) {
        
        /// Properties initialization:
        self.id = id
        self.image = image
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.isSeen = isSeen
        self.account = account
    }
}

// MARK: - Identifiable:

extension NT_Story: Identifiable {  }

// MARK: - Equatable:

extension NT_Story: Equatable {  }

// MARK: - Hashable:

extension NT_Story: Hashable {  }

// MARK: - Example:

extension NT_Story {
    
    // MARK: - Computed properties:
    
    /// An array of the example stories:
    static var example: [NT_Story] {
        [
            .init(
                id: "Item.1",
                image: Images.main62,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                isSeen: false,
                account: NT_Account.example.first { $0.id == "Item.2" }!
            ),
            .init(
                id: "Item.2",
                image: Images.main62,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                isSeen: false,
                account: NT_Account.example.first { $0.id == "Item.3" }!
            ),
            .init(
                id: "Item.3",
                image: Images.main62,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                isSeen: true,
                account: NT_Account.example.first { $0.id == "Item.4" }!
            ),
            .init(
                id: "Item.4",
                image: Images.main62,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                isSeen: true,
                account: NT_Account.example.first { $0.id == "Item.5" }!
            )
        ]
    }
}
