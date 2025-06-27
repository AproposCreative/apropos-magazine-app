//
//  NT_WhiteboardSection.swift
//  Native
//

import Foundation

struct NT_WhiteboardSection {
    
    // MARK: - Properties:
    
    /// Identifier of the section:
    let id: String
    
    /// Title of the section:
    let title: String
    
    /// Icon of the section:
    let icon: String
    
    /// An array of the boards that are part of the section:
    let boards: [NT_WhiteboardBoard]
    
    init(
        id: String,
        title: String,
        icon: String,
        boards: [NT_WhiteboardBoard]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.icon = icon
        self.boards = boards
    }
    
    // MARK: - Computed properties:
    
    /// Count of the boards that are part of the section:
    var boardsCount: Int {
        boards.count
    }
}

// MARK: - Identifiable:

extension NT_WhiteboardSection: Identifiable {  }

// MARK: - Equatable:

extension NT_WhiteboardSection: Equatable {  }

// MARK: - Hashable:

extension NT_WhiteboardSection: Hashable {  }

// MARK: - Example:

extension NT_WhiteboardSection {
    
    // MARK: - Computed properties:
    
    /// An array of the example sections:
    static var example: [NT_WhiteboardSection] {
        [
            .init(
                id: "Item.1",
                title: "All",
                icon: Icons.squareTextSquare,
                boards: NT_WhiteboardBoard.example
            ),
            .init(
                id: "Item.2",
                title: "Recent",
                icon: Icons.clock,
                boards: NT_WhiteboardBoard.example.dropLast(4)
            ),
            .init(
                id: "Item.3",
                title: "Pinned",
                icon: Icons.pin,
                boards: NT_WhiteboardBoard.example.dropLast(6)
            ),
            .init(
                id: "Item.4",
                title: "Shared",
                icon: Icons.personTwo,
                boards: NT_WhiteboardBoard.example.dropLast(5)
            ),
            .init(
                id: "Item.5",
                title: "Archived",
                icon: Icons.archivebox,
                boards: NT_WhiteboardBoard.example.dropLast(7)
            )
        ]
    }
}
