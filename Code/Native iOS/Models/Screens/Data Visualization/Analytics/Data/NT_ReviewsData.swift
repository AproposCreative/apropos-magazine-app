//
//  NT_ReviewsData.swift
//  Native
//

import Foundation

struct NT_ReviewsData {
    
    // MARK: - Properties:
    
    /// Identifier of the data:
    let id: String
    
    /// Value of the data:
    let value: Int
    
    /// Date of the data:
    let date: Date
    
    init(
        id: String,
        value: Int,
        date: Date
    ) {
        
        /// Properties initialization:
        self.id = id
        self.value = value
        self.date = date
    }
}

// MARK: - Identifiable:

extension NT_ReviewsData: Identifiable {  }

// MARK: - Equatable:

extension NT_ReviewsData: Equatable {  }

// MARK: - Hashable:

extension NT_ReviewsData: Hashable {  }

// MARK: - Example:

extension NT_ReviewsData {
    
    // MARK: - Computed properties:
    
    /// An array of the example data:
    static var example: [NT_ReviewsData] {
        [
            .init(
                id: "Item.1",
                value: 200,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 12
                )
            ),
            .init(
                id: "Item.2",
                value: 125,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 13
                )
            ),
            .init(
                id: "Item.3",
                value: 110,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 14
                )
            ),
            .init(
                id: "Item.4",
                value: 50,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 15
                )
            ),
            .init(
                id: "Item.5",
                value: 160,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 16
                )
            )
        ]
    }
}
