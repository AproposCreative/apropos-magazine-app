//
//  NT_ProfileTaskStat.swift
//  Native
//

import Foundation

struct NT_ProfileTaskStat {
    
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

extension NT_ProfileTaskStat: Identifiable {  }

// MARK: - Equatable:

extension NT_ProfileTaskStat: Equatable {  }

// MARK: - Hashable:

extension NT_ProfileTaskStat: Hashable {  }

// MARK: - Example:

extension NT_ProfileTaskStat {
    
    // MARK: - Computed properties:
    
    /// An array of the example stats:
    static var example: [NT_ProfileTaskStat] {
        [
            .init(
                id: "Item.1",
                title: "Tasks",
                value: 1472
            ),
            .init(
                id: "Item.2",
                title: "Projects",
                value: 36
            ),
            .init(
                id: "Item.3",
                title: "Attachments",
                value: 589
            ),
            .init(
                id: "Item.4",
                title: "Comments",
                value: 229
            )
        ]
    }
}
