//
//  NT_ActiveUsersData.swift
//  Native
//

import Foundation

struct NT_ActiveUsersData {
    
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

extension NT_ActiveUsersData: Identifiable {  }

// MARK: - Equatable:

extension NT_ActiveUsersData: Equatable {  }

// MARK: - Hashable:

extension NT_ActiveUsersData: Hashable {  }

// MARK: - Example:

extension NT_ActiveUsersData {
    
    // MARK: - Computed properties:
    
    /// An array of the example data:
    static var example: [NT_ActiveUsersData] {
        [
            .init(
                id: "Item.1",
                value: 12500,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 12
                )
            ),
            .init(
                id: "Item.2",
                value: 17500,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 13
                )
            ),
            .init(
                id: "Item.3",
                value: 5000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 14
                )
            ),
            .init(
                id: "Item.4",
                value: 7500,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 15
                )
            ),
            .init(
                id: "Item.5",
                value: 25000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 16
                )
            ),
            .init(
                id: "Item.6",
                value: 20000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 17
                )
            ),
            .init(
                id: "Item.7",
                value: 2500,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 18
                )
            ),
            .init(
                id: "Item.8",
                value: 15000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 19
                )
            ),
            .init(
                id: "Item.9",
                value: 4762,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 20
                )
            )
        ]
    }
}
