//
//  NT_Color.swift
//  Native
//

import SwiftUI

struct NT_Color {
    
    // MARK: - Properties:
    
    /// Identifier of the color:
    let id: String
    
    /// Title of the color:
    let title: String
    
    /// An actual color:
    let color: Color
    
    /// Starting color of the gradient:
    let gradientStart: Color
    
    /// Ending color of the gradient:
    let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color should have a gradient applied to it:
    let isGradient: Bool
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        isGradient: Bool
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.isGradient = isGradient
    }
}

// MARK: - Identifiable:

extension NT_Color: Identifiable {  }

// MARK: - Equatable:

extension NT_Color: Equatable {  }

// MARK: - Hashable:

extension NT_Color: Hashable {  }

// MARK: - Example:

extension NT_Color {
    
    // MARK: - Computed properties:
    
    /// An array of the example colors:
    static var example: [NT_Color] {
        [
            .init(
                id: "Item.1",
                title: "Blue",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                isGradient: true
            ),
            .init(
                id: "Item.2",
                title: "Orange",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                isGradient: true
            ),
            .init(
                id: "Item.3",
                title: "Purple",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                isGradient: true
            ),
            .init(
                id: "Item.4",
                title: "Pink",
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                isGradient: true
            ),
            .init(
                id: "Item.5",
                title: "Green",
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                isGradient: true
            ),
            .init(
                id: "Item.6",
                title: "Gray",
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd,
                isGradient: true
            )
        ]
    }
}
