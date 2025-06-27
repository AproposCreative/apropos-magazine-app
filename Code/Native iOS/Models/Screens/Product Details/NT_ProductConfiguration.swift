//
//  NT_ProductConfiguration.swift
//  Native
//

import Foundation

struct NT_ProductConfiguration {
    
    // MARK: - Properties:
    
    /// Identifier of the configuration option:
    let id: String
    
    /// Title of the configuration option:
    let title: String
    
    /// Description of the configuration option:
    let description: String
    
    init(
        id: String,
        title: String,
        description: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.description = description
    }
}

// MARK: - Identifiable:

extension NT_ProductConfiguration: Identifiable {  }

// MARK: - Equatable:

extension NT_ProductConfiguration: Equatable {  }

// MARK: - Hashable:

extension NT_ProductConfiguration: Hashable {  }

// MARK: - Example:

extension NT_ProductConfiguration {
    
    // MARK: - Computed properties:
    
    /// An array of the example configuration options:
    static var example: [NT_ProductConfiguration] {
        [
            .init(
                id: "Item.1",
                title: "256 GB",
                description: "3.5 GHz, 16 GB RAM"
            ),
            .init(
                id: "Item.2",
                title: "512 GB",
                description: "4.0 GHz, 24 GB RAM"
            ),
            .init(
                id: "Item.3",
                title: "1 TB",
                description: "4.5 GHz, 32 GB RAM"
            )
        ]
    }
}
