//
//  NT_Budget.swift
//  Native
//

import SwiftUI

struct NT_Budget {
    
    // MARK: - Properties:
    
    /// Identifier of the budget:
    let id: String
    
    /// Title of the budget:
    let title: String
    
    /// Total amount of the budget:
    let totalAmount: Double
    
    /// Used amount of the budget:
    let usedAmount: Double
    
    /// Color of the budget:
    let color: Color
    
    /// Starting color of the gradient of the budget:
    let gradientStart: Color
    
    /// Ending color of the gradient of the budget:
    let gradientEnd: Color
    
    /// Icon of the budget:
    let icon: String
    
    init(
        id: String,
        title: String,
        totalAmount: Double,
        usedAmount: Double,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.totalAmount = totalAmount
        self.usedAmount = usedAmount
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
    }
}

// MARK: - Identifiable:

extension NT_Budget: Identifiable {  }

// MARK: - Equatable:

extension NT_Budget: Equatable {  }

// MARK: - Hashable:

extension NT_Budget: Hashable {  }

// MARK: - Example:

extension NT_Budget {
    
    // MARK: - Computed properties:
    
    /// An array of the example budgets:
    static var example: [NT_Budget] {
        [
            .init(
                id: "Item.1",
                title: "Housing",
                totalAmount: 1500.0,
                usedAmount: 1207.82,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.house
            ),
            .init(
                id: "Item.2",
                title: "Groceries",
                totalAmount: 750.0,
                usedAmount: 378.91,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.bag
            ),
            .init(
                id: "Item.3",
                title: "Transportation",
                totalAmount: 500.0,
                usedAmount: 348.87,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.car
            ),
            .init(
                id: "Item.4",
                title: "Shopping",
                totalAmount: 350.0,
                usedAmount: 0.0,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.cart
            ),
            .init(
                id: "Item.5",
                title: "Entertainment",
                totalAmount: 300.0,
                usedAmount: 59.16,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                icon: Icons.popcorn
            ),
            .init(
                id: "Item.6",
                title: "Miscellaneous",
                totalAmount: 275.0,
                usedAmount: 253.77,
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd,
                icon: Icons.rectangleStack
            )
        ]
    }
}
