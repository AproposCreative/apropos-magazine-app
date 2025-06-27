//
//  NT_ChartBar.swift
//  Native
//

import SwiftUI

struct NT_ChartBar {
    
    // MARK: - Properties:
    
    /// Identifier of the bar of the chart:
    let id: String
    
    /// Title of the bar of the chart:
    let title: String
    
    /// Title of the value of the bar of the chart:
    let valueTitle: String
    
    /// An actual value of the bar of the chart:
    let value: Double
    
    /// Color of the bar of the chart:
    let color: Color
    
    /// Starting color of the gradient of the bar of the chart:
    let gradientStart: Color
    
    /// Ending color of the gradient of the bar of the chart:
    let gradientEnd: Color
    
    init(
        id: String,
        title: String,
        valueTitle: String,
        value: Double,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.valueTitle = valueTitle
        self.value = value
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
    }
}

// MARK: - Identifiable:

extension NT_ChartBar: Identifiable {  }

// MARK: - Equatable:

extension NT_ChartBar: Equatable {  }

// MARK: - Hashable:

extension NT_ChartBar: Hashable {  }

// MARK: - Example:

extension NT_ChartBar {
    
    // MARK: - Computed properties:
    
    /// An array of the example bars of the chart:
    static var example: [NT_ChartBar] {
        [
            .init(
                id: "Item.1",
                title: "Travel",
                valueTitle: "Travel",
                value: 550.00,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd
            ),
            .init(
                id: "Item.2",
                title: "Housing",
                valueTitle: "Housing",
                value: 225.00,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd
            ),
            .init(
                id: "Item.3",
                title: "Shopping",
                valueTitle: "Shopping",
                value: 350.00,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd
            ),
            .init(
                id: "Item.4",
                title: "Entertainment",
                valueTitle: "Entertainment",
                value: 125.00,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd
            ),
            .init(
                id: "Item.5",
                title: "Groceries",
                valueTitle: "Groceries",
                value: 475.00,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd
            ),
            .init(
                id: "Item.6",
                title: "Miscellaneous",
                valueTitle: "Miscellaneous",
                value: 525.00,
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd
            ),
            .init(
                id: "Item.7",
                title: "Subscriptions",
                valueTitle: "Subscriptions",
                value: 225.00,
                color: .yellow,
                gradientStart: .yellowGradientStart,
                gradientEnd: .yellowGradientEnd
            ),
            .init(
                id: "Item.8",
                title: "Transportation",
                valueTitle: "Transportation",
                value: 350.00,
                color: .indigo,
                gradientStart: .indigoGradientStart,
                gradientEnd: .indigoGradientEnd
            ),
            .init(
                id: "Item.9",
                title: "Investing",
                valueTitle: "Investing",
                value: 156.64,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd
            )
        ]
    }
}
