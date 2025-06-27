//
//  NT_File.swift
//  Native
//

import Foundation

struct NT_File {
    
    // MARK: - Properties:
    
    /// Identifier of the file:
    let id: String
    
    /// Title of the file:
    let title: String
    
    /// Size of the file:
    let size: Int64
    
    init(
        id: String,
        title: String,
        size: Int64
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.size = size
    }
}

// MARK: - Identifiable:

extension NT_File: Identifiable {  }

// MARK: - Equatable:

extension NT_File: Equatable {  }

// MARK: - Hashable:

extension NT_File: Hashable {  }

// MARK: - Example:

extension NT_File {
    
    // MARK: - Computed properties:
    
    /// An array of the example files:
    static var example: [NT_File] {
        [
            .init(
                id: "Item.1",
                title: "File - 1",
                size: 25000000000
            ),
            .init(
                id: "Item.2",
                title: "File - 2",
                size: 50000000000
            ),
            .init(
                id: "Item.3",
                title: "File - 3",
                size: 10000000000
            ),
            .init(
                id: "Item.4",
                title: "File - 4",
                size: 5000000000
            ),
            .init(
                id: "Item.5",
                title: "File - 5",
                size: 7500000000
            ),
            .init(
                id: "Item.6",
                title: "File - 6",
                size: 12500000000
            ),
            .init(
                id: "Item.7",
                title: "File - 7",
                size: 150000000000
            ),
            .init(
                id: "Item.8",
                title: "File - 8",
                size: 2500000000000
            ),
            .init(
                id: "Item.9",
                title: "File - 9",
                size: 5000000000000
            ),
            .init(
                id: "Item.10",
                title: "File - 10",
                size: 75000000000
            )
        ]
    }
}
