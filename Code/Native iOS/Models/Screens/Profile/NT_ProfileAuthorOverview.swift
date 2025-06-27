//
//  NT_ProfileOverview.swift
//  Native
//

import SwiftUI

struct NT_ProfileAuthorOverview {
    
    // MARK: - Properties:
    
    /// Identifier of the overview item:
    let id: String
    
    /// Title of the overview item:
    let title: String
    
    /// Value of the overview item:
    let value: Int
    
    /// Color of the overview item:
    let color: Color
    
    /// Starting color of the gradient of the overview item:
    let gradientStart: Color
    
    /// Ending color of the gradient of the overview item:
    let gradientEnd: Color
    
    /// Icon of the overview item:
    let icon: String
    
    init(
        id: String,
        title: String,
        value: Int,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.value = value
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
    }
}

// MARK: - Identifiable:

extension NT_ProfileAuthorOverview: Identifiable {  }

// MARK: - Equatable:

extension NT_ProfileAuthorOverview: Equatable {  }

// MARK: - Hashable:

extension NT_ProfileAuthorOverview: Hashable {  }

// MARK: - Example:

extension NT_ProfileAuthorOverview {
    
    // MARK: - Computed properties:
    
    /// An array of the example overview items:
    static var example: [NT_ProfileAuthorOverview] {
        [
            .init(
                id: "Item.1",
                title: "Subscribers",
                value: 96100,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.person
            ),
            .init(
                id: "Item.2",
                title: "Likes",
                value: 10500,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.heart
            ),
            .init(
                id: "Item.3",
                title: "Comments",
                value: 3200,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.textBubble
            ),
            .init(
                id: "Item.4",
                title: "Articles",
                value: 10,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.docPlaintext
            )
        ]
    }
}
