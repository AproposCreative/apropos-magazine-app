//
//  NT_TotalUsersData.swift
//  Native
//

import Foundation

struct NT_TotalUsersData {
    
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

extension NT_TotalUsersData: Identifiable {  }

// MARK: - Equatable:

extension NT_TotalUsersData: Equatable {  }

// MARK: - Hashable:

extension NT_TotalUsersData: Hashable {  }

// MARK: - Example:

extension NT_TotalUsersData {
    
    // MARK: - Computed properties:
    
    /// An array of the example data:
    static var example: [NT_TotalUsersData] {
        [
            .init(
                id: "Item.1",
                value: 135000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 12
                )
            ),
            .init(
                id: "Item.2",
                value: 162336,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 13
                )
            ),
            .init(
                id: "Item.3",
                value: 135000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 14
                )
            ),
            .init(
                id: "Item.4",
                value: 135000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 15
                )
            ),
            .init(
                id: "Item.5",
                value: 175000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 16
                )
            ),
            .init(
                id: "Item.6",
                value: 150000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 17
                )
            ),
            .init(
                id: "Item.7",
                value: 300000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 18
                )
            ),
            .init(
                id: "Item.8",
                value: 350000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 19
                )
            ),
            .init(
                id: "Item.9",
                value: 350000,
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
