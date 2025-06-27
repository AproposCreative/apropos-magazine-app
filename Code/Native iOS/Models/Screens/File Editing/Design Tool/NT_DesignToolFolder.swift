//
//  NT_DesignToolFolder.swift
//  Native
//

import Foundation

struct NT_DesignToolFolder {
    
    // MARK: - Properties:
    
    /// Identifier of the folder:
    let id: String
    
    /// Title of the folder:
    let title: String
    
    /// Icon of the folder:
    let icon: String
    
    /// An array of the files that are part of the folder:
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
    
    /// Count of the files that are part of the folder:
    var filesCount: Int {
        files.count
    }
}

// MARK: - Identifiable:

extension NT_DesignToolFolder: Identifiable {  }

// MARK: - Equatable:

extension NT_DesignToolFolder: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolFolder: Hashable {  }

// MARK: - Example:

extension NT_DesignToolFolder {
    
    // MARK: - Computed properties:
    
    /// An array of the example folders:
    static var example: [NT_DesignToolFolder] {
        [
            .init(
                id: "Item.1",
                title: "Ideas and Inspiration",
                icon: Icons.folder,
                files: .init(NT_DesignToolFile.example.prefix(4))
            ),
            .init(
                id: "Item.2",
                title: "Web Design Projects",
                icon: Icons.folder,
                files: NT_DesignToolFile.example.suffix(6)
            ),
            .init(
                id: "Item.3",
                title: "Mobile App UI",
                icon: Icons.folder,
                files: .init(NT_DesignToolFile.example.prefix(2))
            ),
            .init(
                id: "Item.4",
                title: "Branding",
                icon: Icons.folder,
                files: NT_DesignToolFile.example.suffix(3)
            ),
            .init(
                id: "Item.5",
                title: "Social Media Templates",
                icon: Icons.folder,
                files: NT_DesignToolFile.example.suffix(1)
            )
        ]
    }
}
