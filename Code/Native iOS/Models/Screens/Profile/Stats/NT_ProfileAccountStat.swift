//
//  NT_ProfileAccountStat.swift
//  Native
//

import Foundation

struct NT_ProfileAccountStat {
    
    // MARK: - Properties:
    
    /// Identifier of the stat:
    let id: String
    
    /// Title of the stat:
    let title: String
    
    /// Value of the stat:
    let value: Int
    
    init(
        id: String,
        title: String,
        value: Int
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.value = value
    }
}

// MARK: - Identifiable:

extension NT_ProfileAccountStat: Identifiable {  }

// MARK: - Equatable:

extension NT_ProfileAccountStat: Equatable {  }

// MARK: - Hashable:

extension NT_ProfileAccountStat: Hashable {  }

// MARK: - Example:

extension NT_ProfileAccountStat {
    
    // MARK: - Computed properties:
    
    /// An array of the example stats:
    static var example: [NT_ProfileAccountStat] {
        [
            .init(
                id: "Item.1",
                title: "Followers",
                value: 96100
            ),
            .init(
                id: "Item.2",
                title: "Likes",
                value: 10500
            ),
            .init(
                id: "Item.3",
                title: "Comments",
                value: 3200
            )
        ]
    }
}
