//
//  NT_InvestmentValue.swift
//  Native
//

import Foundation

struct NT_InvestmentValue {
    
    // MARK: - Properties:
    
    /// Identifier of the value of the investment:
    let id: String
    
    /// An actual value of the value of the investment:
    let value: Double
    
    /// Date of the value of the investment:
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

extension NT_InvestmentValue: Identifiable {  }

// MARK: - Equatable:

extension NT_InvestmentValue: Equatable {  }

// MARK: - Hashable:

extension NT_InvestmentValue: Hashable {  }

// MARK: - Example:

extension NT_InvestmentValue {
    
    // MARK: - Computed properties:
    
    /// An array of the example values of the investments:
    static var example: [NT_InvestmentValue] {
        [
            .init(
                id: "Item.1",
                value: 150000.00,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5
                )
            ),
            .init(
                id: "Item.2",
                value: 200000.00,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 4
                )
            ),
            .init(
                id: "Item.3",
                value: 50000.00,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 3
                )
            )
        ]
    }
}
