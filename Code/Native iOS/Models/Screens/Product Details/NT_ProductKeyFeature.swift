//
//  NT_ProductKeyFeature.swift
//  Native
//

import Foundation

struct NT_ProductKeyFeature {
    
    // MARK: - Properties:
    
    /// Identifier of the feature:
    let id: String
    
    /// Title of the feature:
    let title: String
    
    /// Value of the feature:
    let value: String
    
    init(
        id: String,
        title: String,
        value: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.value = value
    }
}

// MARK: - Identifiable:

extension NT_ProductKeyFeature: Identifiable {  }

// MARK: - Equatable:

extension NT_ProductKeyFeature: Equatable {  }

// MARK: - Hashable:

extension NT_ProductKeyFeature: Hashable {  }

// MARK: - Example:

extension NT_ProductKeyFeature {
    
    // MARK: - Computed properties:
    
    /// An array of the example features:
    static var example: [NT_ProductKeyFeature] {
        [
            .init(
                id: "Item.1",
                title: "Storage",
                value: "512 GB"
            ),
            .init(
                id: "Item.2",
                title: "CPU",
                value: "12 Core"
            ),
            .init(
                id: "Item.3",
                title: "GPU",
                value: "8 Core"
            ),
            .init(
                id: "Item.4",
                title: "Color",
                value: "Space Gray"
            ),
            .init(
                id: "Item.5",
                title: "Charger",
                value: "Included"
            )
        ]
    }
}
