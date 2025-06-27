//
//  NT_ProductStorage.swift
//  Native
//

import Foundation

struct NT_ProductStorage {
    
    // MARK: - Properties:
    
    /// Identifier of the storage option:
    let id: String
    
    /// Title of the storage option:
    let title: String
    
    init(
        id: String,
        title: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
    }
}

// MARK: - Identifiable:

extension NT_ProductStorage: Identifiable {  }

// MARK: - Equatable:

extension NT_ProductStorage: Equatable {  }

// MARK: - Hashable:

extension NT_ProductStorage: Hashable {  }

// MARK: - Example:

extension NT_ProductStorage {
    
    // MARK: - Computed properties:
    
    /// An array of the example storage options:
    static var example: [NT_ProductStorage] {
        [
            .init(
                id: "Item.1",
                title: "256 GB"
            ),
            .init(
                id: "Item.2",
                title: "512 GB"
            )
        ]
    }
}
