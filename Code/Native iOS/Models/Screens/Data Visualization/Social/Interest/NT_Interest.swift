//
//  NT_Interest.swift
//  Native
//

import SwiftUI

struct NT_Interest {
    
    // MARK: - Properties:
    
    /// Identifier of the interest:
    let id: String
    
    /// Title of the interest:
    let title: String
    
    /// Value of the interest:
    let value: Double
    
    /// Color of the interest:
    let color: Color
    
    /// Starting color of the gradient of the interest:
    let gradientStart: Color
    
    /// Ending color of the gradient of the interest:
    let gradientEnd: Color
    
    init(
        id: String,
        title: String,
        value: Double,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.value = value
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
    }
}

// MARK: - Identifiable:

extension NT_Interest: Identifiable {  }

// MARK: - Equatable:

extension NT_Interest: Equatable {  }

// MARK: - Hashable:

extension NT_Interest: Hashable {  }

// MARK: - Example:

extension NT_Interest {
    
    // MARK: - Computed properties:
    
    /// An array of the example interests:
    static var example: [NT_Interest] {
        [
            .init(
                id: "Item.1",
                title: "Travel",
                value: 0.1,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd
            ),
            .init(
                id: "Item.2",
                title: "Shopping",
                value: 0.25,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd
            ),
            .init(
                id: "Item.3",
                title: "Design",
                value: 0.1,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd
            ),
            .init(
                id: "Item.4",
                title: "Software",
                value: 0.15,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd
            ),
            .init(
                id: "Item.5",
                title: "Adventure",
                value: 0.1,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd
            ),
            .init(
                id: "Item.6",
                title: "Photography",
                value: 0.05,
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd
            ),
            .init(
                id: "Item.7",
                title: "Music",
                value: 0.05,
                color: .yellow,
                gradientStart: .yellowGradientStart,
                gradientEnd: .yellowGradientEnd
            ),
            .init(
                id: "Item.7",
                title: "Fashion",
                value: 0.20,
                color: .indigo,
                gradientStart: .indigoGradientStart,
                gradientEnd: .indigoGradientEnd
            )
        ]
    }
}
