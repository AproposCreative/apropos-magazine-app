//
//  NT_ChartLineValue.swift
//  Native
//

import Foundation

struct NT_ChartLineValue {
    
    // MARK: - Properties:
    
    /// Identifier of the value of the line of the chart:
    let id: String
    
    /// An actual value of the value of the line of the chart:
    let value: Double
    
    /// Date of the value of the line of the chart:
    let date: Date
    
    init(
        id: String,
        value: Double,
        date: Date
    ) {
        
        /// Properties initialization:
        self.id = id
        self.value = value
        self.date = date
    }
}

// MARK: - Identifiable:

extension NT_ChartLineValue: Identifiable {  }

// MARK: - Equatable:

extension NT_ChartLineValue: Equatable {  }

// MARK: - Hashable:

extension NT_ChartLineValue: Hashable {  }

// MARK: - Example:

extension NT_ChartLineValue {
    
    // MARK: - Computed properties:
    
    /// An array of the example of the values of the lines of the chart:
    static var example: [NT_ChartLineValue] {
        [
            .init(
                id: "Item.1",
                value: 50.00,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 3
                )
            ),
            .init(
                id: "Item.2",
                value: 100.00,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 4
                )
            ),
            .init(
                id: "Item.3",
                value: 150.00,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5
                )
            )
        ]
    }
}
