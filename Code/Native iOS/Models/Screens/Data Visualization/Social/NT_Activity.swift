//
//  NT_Activity.swift
//  Native
//

import SwiftUI

struct NT_Activity {
    
    // MARK: - Properties:
    
    /// Identifier of the activity:
    let id: String
    
    /// Title of the activity:
    let title: String
    
    /// Description of the activity:
    let description: String
    
    /// Value of the activity:
    let value: Int
    
    /// Color of the activity:
    let color: Color
    
    /// Starting color of the gradient of the activity:
    let gradientStart: Color
    
    /// Ending color of the gradient of the activity:
    let gradientEnd: Color
    
    /// Icon of the activity:
    let icon: String
    
    init(
        id: String,
        title: String,
        description: String,
        value: Int,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.description = description
        self.value = value
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
    }
}

// MARK: - Identifiable:

extension NT_Activity: Identifiable {  }

// MARK: - Equatable:

extension NT_Activity: Equatable {  }

// MARK: - Hashable:

extension NT_Activity: Hashable {  }

// MARK: - Example:

extension NT_Activity {
    
    // MARK: - Computed properties:
    
    /// An array of the example activities:
    static var example: [NT_Activity] {
        [
            .init(
                id: "Item.1",
                title: "Comments",
                description: "10% increase",
                value: 457,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.textBubble
            ),
            .init(
                id: "Item.2",
                title: "Likes",
                description: "18% decrease",
                value: 45300,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.heart
            ),
            .init(
                id: "Item.3",
                title: "Bookmarks",
                description: "75% decrease",
                value: 132,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.bookmark
            ),
            .init(
                id: "Item.4",
                title: "Unfollows",
                description: "1% increase",
                value: 27,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.minusCircle
            )
        ]
    }
}
