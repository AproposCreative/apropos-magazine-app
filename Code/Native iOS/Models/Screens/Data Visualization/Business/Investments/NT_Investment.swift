//
//  NT_Investment.swift
//  Native
//

import SwiftUI

struct NT_Investment {
    
    // MARK: - Properties:
    
    /// Identifier of the investment:
    let id: String
    
    /// Title of the investment:
    let title: String
    
    /// Color of the investment:
    let color: Color
    
    /// Starting color of the gradient of the investment:
    let gradientStart: Color
    
    /// Ending color of the gradient of the investment:
    let gradientEnd: Color
    
    /// An array of the values of the investment:
    let values: [NT_InvestmentValue]
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        values: [NT_InvestmentValue]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.values = values
    }
}

// MARK: - Identifiable:

extension NT_Investment: Identifiable {  }

// MARK: - Equatable:

extension NT_Investment: Equatable {  }

// MARK: - Hashable:

extension NT_Investment: Hashable {  }

// MARK: - Example:

extension NT_Investment {
    
    // MARK: - Computed properties:
    
    /// An array of the example investments:
    static var example: [NT_Investment] {
        [
            .init(
                id: "Item.1",
                title: "Savings",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 5500000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 3000000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 3500000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 2500000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 4500000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 6
                        )
                    )
                ]
            ),
            .init(
                id: "Item.2",
                title: "Stocks and Shares",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 4000000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 2500000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 3000000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 2000000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 3500000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 6
                        )
                    )
                ]
            ),
            .init(
                id: "Item.3",
                title: "Real Estate",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 3000000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 1500000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 2250000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 1250000.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 2577239.45,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 6
                        )
                    )
                ]
            )
        ]
    }
}
