//
//  NT_IncomeCategory.swift
//  Native
//

import SwiftUI

struct NT_IncomeCategory {
    
    // MARK: - Properties:
    
    /// Identifier of the category:
    let id: String
    
    /// Title of the category:
    let title: String
    
    /// Amount of the category:
    let amount: Double
    
    /// Color of the category:
    let color: Color
    
    /// Starting color of the gradient of the category:
    let gradientStart: Color
    
    /// Ending color of the gradient of the category:
    let gradientEnd: Color
    
    init(
        id: String,
        title: String,
        amount: Double,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.amount = amount
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
    }
}

// MARK: - Identifiable:

extension NT_IncomeCategory: Identifiable {  }

// MARK: - Equatable:

extension NT_IncomeCategory: Equatable {  }

// MARK: - Hashable:

extension NT_IncomeCategory: Hashable {  }

// MARK: - Example:

extension NT_IncomeCategory {
    
    // MARK: - Computed properties:
    
    /// An array of the example categories:
    static var example: [NT_IncomeCategory] {
        [
            .init(
                id: "Item.1",
                title: "Advertising Revenue",
                amount: 350000.0,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd
            ),
            .init(
                id: "Item.2",
                title: "Subscription Fees",
                amount: 500000.0,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd
            ),
            .init(
                id: "Item.3",
                title: "Rental Income",
                amount: 100000.0,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd
            ),
            .init(
                id: "Item.4",
                title: "Software Sales",
                amount: 150000.0,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd
            ),
            .init(
                id: "Item.5",
                title: "Product Sales",
                amount: 892648.27,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd
            ),
            .init(
                id: "Item.6",
                title: "Service Revenue",
                amount: 600000.0,
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd
            ),
            .init(
                id: "Item.7",
                title: "Interest Income",
                amount: 100000.0,
                color: .yellow,
                gradientStart: .yellowGradientStart,
                gradientEnd: .yellowGradientEnd
            ),
            .init(
                id: "Item.8",
                title: "Licensing Fees",
                amount: 250000.0,
                color: .indigo,
                gradientStart: .indigoGradientStart,
                gradientEnd: .indigoGradientEnd
            ),
            .init(
                id: "Item.9",
                title: "Affiliate Income",
                amount: 100000.0,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd
            )
        ]
    }
}
