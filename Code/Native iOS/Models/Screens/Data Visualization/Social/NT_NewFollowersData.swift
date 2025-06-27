//
//  NT_NewFollowersData.swift
//  Native
//

import Foundation

struct NT_NewFollowersData {
    
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

extension NT_NewFollowersData: Identifiable {  }

// MARK: - Equatable:

extension NT_NewFollowersData: Equatable {  }

// MARK: - Hashable:

extension NT_NewFollowersData: Hashable {  }

// MARK: - Example:

extension NT_NewFollowersData {
    
    // MARK: - Computed properties:
    
    /// An array of the example data:
    static var example: [NT_NewFollowersData] {
        [
            .init(
                id: "Item.1",
                value: 325,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 29
                )
            ),
            .init(
                id: "Item.2",
                value: 656,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 30
                )
            ),
            .init(
                id: "Item.3",
                value: 410,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 31
                )
            ),
            .init(
                id: "Item.4",
                value: 500,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 1
                )
            ),
            .init(
                id: "Item.5",
                value: 250,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 2
                )
            ),
            .init(
                id: "Item.6",
                value: 400,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 3
                )
            ),
            .init(
                id: "Item.7",
                value: 200,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 4
                )
            ),
            .init(
                id: "Item.8",
                value: 500,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5
                )
            ),
            .init(
                id: "Item.9",
                value: 410,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 6
                )
            )
        ]
    }
}
