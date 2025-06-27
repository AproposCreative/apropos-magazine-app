//
//  NT_ChartLine.swift
//  Native
//

import SwiftUI

struct NT_ChartLine {
    
    // MARK: - Properties:
    
    /// Identifier of the line of the chart:
    let id: String
    
    /// Title of the line of the chart:
    let title: String
    
    /// Color of the line of the chart:
    let color: Color
    
    /// Starting color of the gradient of the line of the chart:
    let gradientStart: Color
    
    /// Ending color of the gradient of the line of the chart:
    let gradientEnd: Color
    
    /// An array of the actual values of the line of the chart:
    let values: [NT_ChartLineValue]
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        values: [NT_ChartLineValue]
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

extension NT_ChartLine: Identifiable {  }

// MARK: - Equatable:

extension NT_ChartLine: Equatable {  }

// MARK: - Hashable:

extension NT_ChartLine: Hashable {  }

// MARK: - Example:

extension NT_ChartLine {
    
    // MARK: - Computed properties:
    
    /// An array of the example of the lines of the chart:
    static var example: [NT_ChartLine] {
        [
            .init(
                id: "Item.1",
                title: "Travel",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 550.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 1
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 200.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 625.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 225.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 150.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    )
                ]
            ),
            .init(
                id: "Item.2",
                title: "Housing",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 225.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 1
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 750.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 1500.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 275.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 25.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    )
                ]
            ),
            .init(
                id: "Item.3",
                title: "Shopping",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 25.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 1
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 125.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 1250.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 550.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 475.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    )
                ]
            ),
            .init(
                id: "Item.4",
                title: "Entertainment",
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 950.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 1
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 700.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 545.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 25.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 45.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    )
                ]
            ),
            .init(
                id: "Item.5",
                title: "Groceries",
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 95.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 1
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 100.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 875.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 135.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 90.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    )
                ]
            ),
            .init(
                id: "Item.6",
                title: "Miscellaneous",
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 800.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 1
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 650.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 975.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 1100.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 575.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    )
                ]
            ),
            .init(
                id: "Item.7",
                title: "Subscriptions",
                color: .yellow,
                gradientStart: .yellowGradientStart,
                gradientEnd: .yellowGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 1425.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 1
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 50.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 75.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 80.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 195.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    )
                ]
            ),
            .init(
                id: "Item.8",
                title: "Transportation",
                color: .indigo,
                gradientStart: .indigoGradientStart,
                gradientEnd: .indigoGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 415.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 1
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 250.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 1025.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 750.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 345.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    )
                ]
            ),
            .init(
                id: "Item.9",
                title: "Investing",
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                values: [
                    .init(
                        id: "Item.1",
                        value: 100.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 1
                        )
                    ),
                    .init(
                        id: "Item.2",
                        value: 250.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 2
                        )
                    ),
                    .init(
                        id: "Item.3",
                        value: 25.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 3
                        )
                    ),
                    .init(
                        id: "Item.4",
                        value: 80.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 4
                        )
                    ),
                    .init(
                        id: "Item.5",
                        value: 90.00,
                        date: .dateWithComponents(
                            withYear: 2024,
                            withMonth: 8,
                            withDay: 5
                        )
                    )
                ]
            )
        ]
    }
}
