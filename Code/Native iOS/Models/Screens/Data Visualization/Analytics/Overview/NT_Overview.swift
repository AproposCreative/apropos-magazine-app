//
//  NT_Overview.swift
//  Native
//

import SwiftUI

struct NT_Overview {
    
    // MARK: - Properties:
    
    /// Identifier of the overview item:
    let id: String
    
    /// Title of the overview item:
    let title: String
    
    /// Description of the overview item:
    let description: String
    
    /// Value of the overview item:
    let value: Double
    
    /// Color of the overview item:
    let color: Color
    
    /// Starting color of the gradient of the overview item:
    let gradientStart: Color
    
    /// Ending color of the gradient of the overview item:
    let gradientEnd: Color
    
    /// Icon of the overview item:
    let icon: String
    
    /// Type of the overview item:
    let type: NT_OverviewType
    
    init(
        id: String,
        title: String,
        description: String,
        value: Double,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String,
        type: NT_OverviewType
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
        self.type = type
    }
}

// MARK: - Identifiable:

extension NT_Overview: Identifiable {  }

// MARK: - Equatable:

extension NT_Overview: Equatable {  }

// MARK: - Hashable:

extension NT_Overview: Hashable {  }

// MARK: - Example:

extension NT_Overview {
    
    // MARK: - Computed properties:
    
    /// An array of the example overview items:
    static var example: [NT_Overview] {
        [
            .init(
                id: "Item.1",
                title: "Revenue",
                description: "50% increase",
                value: 55200.0,
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.dollarsign,
                type: .amount
            ),
            .init(
                id: "Item.2",
                title: "MRR",
                description: "3% increase",
                value: 39700.0,
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.chartLineUptrendXYAxis,
                type: .amount
            ),
            .init(
                id: "Item.3",
                title: "Proceeds",
                description: "54% increase",
                value: 48100.0,
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.creditcard,
                type: .amount
            ),
            .init(
                id: "Item.4",
                title: "Refunds",
                description: "9% decrease",
                value: 143.0,
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.arrowCounterclockwise,
                type: .amount
            ),
            .init(
                id: "Item.5",
                title: "Conversion Rate",
                description: "No change",
                value: 0.53,
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                icon: Icons.percent,
                type: .percentage
            ),
            .init(
                id: "Item.6",
                title: "Churn Rate",
                description: "18% decrease",
                value: 0.74,
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd,
                icon: Icons.xmarkCircle,
                type: .percentage
            )
        ]
    }
}
