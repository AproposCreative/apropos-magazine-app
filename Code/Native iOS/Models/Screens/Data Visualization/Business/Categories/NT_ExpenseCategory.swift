//
//  NT_ExpenseCategory.swift
//  Native
//

import SwiftUI

struct NT_ExpenseCategory {
    
    // MARK: - Properties:
    
    /// Identifier of the category:
    let id: String
    
    /// Title of the category:
    let title: String
    
    /// Description of the category:
    let description: String
    
    /// Amount of the category:
    let amount: Double
    
    /// Color of the category:
    let color: Color
    
    /// Starting color of the gradient of the category:
    let gradientStart: Color
    
    /// Ending color of the gradient of the category:
    let gradientEnd: Color
    
    /// Icon of the category:
    let icon: String
    
    init(
        id: String,
        title: String,
        description: String,
        amount: Double,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.description = description
        self.amount = amount
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
    }
}

// MARK: - Identifiable:

extension NT_ExpenseCategory: Identifiable {  }

// MARK: - Equatable:

extension NT_ExpenseCategory: Equatable {  }

// MARK: - Hashable:

extension NT_ExpenseCategory: Hashable {  }

// MARK: - Example:

extension NT_ExpenseCategory {
    
    // MARK: - Computed properties:
    
    /// An array of the example categories:
    static var example1: [NT_ExpenseCategory] {
        [
            .init(
                id: "Item.1",
                title: "Office Expenses",
                description: "5 transactions",
                amount: 20400.0,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.building
            ),
            .init(
                id: "Item.2",
                title: "Payroll",
                description: "24 transactions",
                amount: 407500.0,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.dollarsign
            ),
            .init(
                id: "Item.3",
                title: "Contract Services",
                description: "18 transactions",
                amount: 45000.0,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.docPlaintext
            ),
            .init(
                id: "Item.4",
                title: "Marketing",
                description: "12 transactions",
                amount: 5200.0,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.megaphone
            ),
            .init(
                id: "Item.5",
                title: "Software",
                description: "36 transactions",
                amount: 1700.0,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.desktopcomputer
            ),
            .init(
                id: "Item.6",
                title: "Taxes",
                description: "1 transaction",
                amount: 246900.0,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                icon: Icons.percent
            ),
            .init(
                id: "Item.7",
                title: "Miscellaneous",
                description: "3 transactions",
                amount: 683.07,
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd,
                icon: Icons.rectangleStack
            ),
            .init(
                id: "Item.8",
                title: "Transportation",
                description: "12 transactions",
                amount: 12500.0,
                color: .yellow,
                gradientStart: .yellowGradientStart,
                gradientEnd: .yellowGradientEnd,
                icon: Icons.car
            ),
            .init(
                id: "Item.9",
                title: "Suppliers",
                description: "7 transactions",
                amount: 40000.0,
                color: .indigo,
                gradientStart: .indigoGradientStart,
                gradientEnd: .indigoGradientEnd,
                icon: Icons.mailStack
            )
        ]
    }
    
    /// An array of the example categories:
    static var example2: [NT_ExpenseCategory] {
        [
            .init(
                id: "Item.1",
                title: "Travel",
                description: "2 transactions",
                amount: 550.00,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.airplane
            ),
            .init(
                id: "Item.2",
                title: "Housing",
                description: "1 transaction",
                amount: 225.00,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.house
            ),
            .init(
                id: "Item.3",
                title: "Shopping",
                description: "5 transactions",
                amount: 350.00,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.cart
            ),
            .init(
                id: "Item.4",
                title: "Entertainment",
                description: "3 transactions",
                amount: 125.00,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.popcorn
            ),
            .init(
                id: "Item.5",
                title: "Groceries",
                description: "10 transactions",
                amount: 475.00,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                icon: Icons.bag
            ),
            .init(
                id: "Item.6",
                title: "Miscellaneous",
                description: "8 transactions",
                amount: 525.00,
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd,
                icon: Icons.rectangleStack
            ),
            .init(
                id: "Item.7",
                title: "Subscriptions",
                description: "4 transactions",
                amount: 225.00,
                color: .yellow,
                gradientStart: .yellowGradientStart,
                gradientEnd: .yellowGradientEnd,
                icon: Icons.repeatIcon
            ),
            .init(
                id: "Item.8",
                title: "Transportation",
                description: "2 transactions",
                amount: 350.00,
                color: .indigo,
                gradientStart: .indigoGradientStart,
                gradientEnd: .indigoGradientEnd,
                icon: Icons.car
            ),
            .init(
                id: "Item.9",
                title: "Investing",
                description: "1 transaction",
                amount: 156.64,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                icon: Icons.chartLineUptrendXYAxis
            )
        ]
    }
}
