//
//  NT_WhiteboardBoard.swift
//  Native
//

import Foundation

struct NT_WhiteboardBoard {
    
    // MARK: - Properties:
    
    /// Identifier of the board:
    let id: String
    
    /// Title of the board:
    let title: String
    
    /// Icon of the board:
    let icon: String
    
    /// 'Bool' value indicating whether or not the board is shared with the team:
    let isTeam: Bool
    
    /// An array of the notes that are part of the board:
    let notes: [NT_WhiteboardNote]
    
    init(
        id: String,
        title: String,
        icon: String,
        isTeam: Bool,
        notes: [NT_WhiteboardNote]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.icon = icon
        self.isTeam = isTeam
        self.notes = notes
    }
}

// MARK: - Identifiable:

extension NT_WhiteboardBoard: Identifiable {  }

// MARK: - Equatable:

extension NT_WhiteboardBoard: Equatable {  }

// MARK: - Hashable:

extension NT_WhiteboardBoard: Hashable {  }

// MARK: - Example:

extension NT_WhiteboardBoard {
    
    // MARK: - Computed properties:
    
    /// An array of the example boards:
    static var example: [NT_WhiteboardBoard] {
        [
            .init(
                id: "Item.1",
                title: "Home Renovation",
                icon: Icons.squareTextSquare,
                isTeam: false,
                notes: NT_WhiteboardNote.example
            ),
            .init(
                id: "Item.2",
                title: "New Kitchen Layout",
                icon: Icons.squareTextSquare,
                isTeam: false,
                notes: NT_WhiteboardNote.example
            ),
            .init(
                id: "Item.3",
                title: "Summer Vacation",
                icon: Icons.squareTextSquare,
                isTeam: false,
                notes: NT_WhiteboardNote.example
            ),
            .init(
                id: "Item.4",
                title: "Planning Q4 2024",
                icon: Icons.squareTextSquare,
                isTeam: true,
                notes: NT_WhiteboardNote.example
            ),
            .init(
                id: "Item.5",
                title: "Web Design Project",
                icon: Icons.squareTextSquare,
                isTeam: true,
                notes: NT_WhiteboardNote.example
            ),
            .init(
                id: "Item.6",
                title: "App Development",
                icon: Icons.squareTextSquare,
                isTeam: true,
                notes: NT_WhiteboardNote.example
            ),
            .init(
                id: "Item.7",
                title: "Information Architecture",
                icon: Icons.squareTextSquare,
                isTeam: true,
                notes: NT_WhiteboardNote.example
            ),
            .init(
                id: "Item.8",
                title: "Hiring Process",
                icon: Icons.squareTextSquare,
                isTeam: true,
                notes: NT_WhiteboardNote.example
            )
        ]
    }
}
