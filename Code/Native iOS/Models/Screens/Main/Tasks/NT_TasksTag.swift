//
//  NT_TasksTag.swift
//  Native
//

import SwiftUI

struct NT_TasksTag {
    
    // MARK: - Properties:
    
    /// Identifier of the tag:
    let id: String
    
    /// Title of the tag:
    let title: String
    
    /// Color of the tag:
    let color: Color
    
    /// Starting color of the gradient of the tag:
    let gradientStart: Color
    
    /// Ending color of the gradient of the tag:
    let gradientEnd: Color
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
    }
}

// MARK: - Identifiable:

extension NT_TasksTag: Identifiable {  }

// MARK: - Equatable:

extension NT_TasksTag: Equatable {  }

// MARK: - Hashable:

extension NT_TasksTag: Hashable {  }

// MARK: - Example:

extension NT_TasksTag {
    
    // MARK: - Computed properties:
    
    /// An array of the example tags:
    static var example: [NT_TasksTag] {
        [
            .init(
                id: "Item.1",
                title: "Urgent",
                color: .red,
                gradientStart: .redGradientStart,
                gradientEnd: .redGradientEnd
            ),
            .init(
                id: "Item.2",
                title: "Design",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd
            ),
            .init(
                id: "Item.3",
                title: "Coming Soon",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd
            ),
            .init(
                id: "Item.4",
                title: "Meetings",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd
            ),
            .init(
                id: "Item.5",
                title: "Low Priority",
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd
            ),
            .init(
                id: "Item.6",
                title: "1:1's",
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd
            )
        ]
    }
}
