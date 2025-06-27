//
//  NT_DesignToolTag.swift
//  Native
//

import Foundation

struct NT_DesignToolTag {
    
    // MARK: - Properties:
    
    /// Identifier of the tag:
    let id: String
    
    /// Title of the tag:
    let title: String
    
    /// Icon of the tag:
    let icon: String
    
    /// An array of the files that are part of the tag:
    let files: [NT_DesignToolFile]
    
    init(
        id: String,
        title: String,
        icon: String,
        files: [NT_DesignToolFile]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.icon = icon
        self.files = files
    }
    
    // MARK: - Computed properties:
    
    /// Count of the files that are part of the tag:
    var filesCount: Int {
        files.count
    }
}

// MARK: - Identifiable:

extension NT_DesignToolTag: Identifiable {  }

// MARK: - Equatable:

extension NT_DesignToolTag: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolTag: Hashable {  }

// MARK: - Example:

extension NT_DesignToolTag {
    
    // MARK: - Computed properties:
    
    /// An array of the example tags:
    static var example: [NT_DesignToolTag] {
        [
            .init(
                id: "Item.1",
                title: "Trending",
                icon: Icons.number,
                files: NT_DesignToolFile.example.filter { $0.tags.contains("Item.1") }
            ),
            .init(
                id: "Item.2",
                title: "Personal Projects",
                icon: Icons.number,
                files: NT_DesignToolFile.example.filter { $0.tags.contains("Item.2") }
            ),
            .init(
                id: "Item.3",
                title: "Drafts",
                icon: Icons.number,
                files: NT_DesignToolFile.example.filter { $0.tags.contains("Item.3") }
            ),
            .init(
                id: "Item.4",
                title: "Client Review",
                icon: Icons.number,
                files: NT_DesignToolFile.example.filter { $0.tags.contains("Item.4") }
            ),
            .init(
                id: "Item.5",
                title: "Obsolete",
                icon: Icons.number,
                files: NT_DesignToolFile.example.filter { $0.tags.contains("Item.5") }
            ),
            .init(
                id: "Item.6",
                title: "Low-fidelity Wireframes",
                icon: Icons.number,
                files: NT_DesignToolFile.example.filter { $0.tags.contains("Item.6") }
            ),
            .init(
                id: "Item.7",
                title: "Device Mockups",
                icon: Icons.number,
                files: NT_DesignToolFile.example.filter { $0.tags.contains("Item.7") }
            ),
            .init(
                id: "Item.8",
                title: "In Progress",
                icon: Icons.number,
                files: NT_DesignToolFile.example.filter { $0.tags.contains("Item.8") }
            ),
            .init(
                id: "Item.9",
                title: "UI Components",
                icon: Icons.number,
                files: NT_DesignToolFile.example.filter { $0.tags.contains("Item.9") }
            ),
            .init(
                id: "Item.10",
                title: "Templates",
                icon: Icons.number,
                files: NT_DesignToolFile.example.filter { $0.tags.contains("Item.10") }
            )
        ]
    }
}
