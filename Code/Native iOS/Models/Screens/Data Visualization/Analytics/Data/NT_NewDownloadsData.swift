//
//  NT_NewDownloadsData.swift
//  Native
//

import Foundation

struct NT_NewDownloadsData {
    
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

extension NT_NewDownloadsData: Identifiable {  }

// MARK: - Equatable:

extension NT_NewDownloadsData: Equatable {  }

// MARK: - Hashable:

extension NT_NewDownloadsData: Hashable {  }

// MARK: - Example:

extension NT_NewDownloadsData {
    
    // MARK: - Computed properties:
    
    /// An array of the example data:
    static var example: [NT_NewDownloadsData] {
        [
            .init(
                id: "Item.1",
                value: 2000,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 12
                )
            ),
            .init(
                id: "Item.2",
                value: 375,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 13
                )
            ),
            .init(
                id: "Item.3",
                value: 2506,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 14
                )
            ),
            .init(
                id: "Item.4",
                value: 1500,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 5,
                    withHour: 15
                )
            ),
            .init(
                id: "Item.5",
                value: 700,
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
