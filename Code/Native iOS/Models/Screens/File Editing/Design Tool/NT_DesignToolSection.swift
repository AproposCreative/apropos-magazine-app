//
//  NT_DesignToolSection.swift
//  Native
//

import Foundation

struct NT_DesignToolSection {
    
    // MARK: - Properties:
    
    /// Identifier of the section:
    let id: String
    
    /// Title of the section:
    let title: String
    
    /// Icon of the section:
    let icon: String
    
    /// An array of the files of the section:
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
    
    /// Count of the files of the section:
    var filesCount: Int {
        files.count
    }
}

// MARK: - Identifiable:

extension NT_DesignToolSection: Identifiable {  }

// MARK: - Equatable:

extension NT_DesignToolSection: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolSection: Hashable {  }

// MARK: - Example:

extension NT_DesignToolSection {
    
    // MARK: - Computed properties:
    
    /// An array of the example sections:
    static var example: [NT_DesignToolSection] {
        [
            .init(
                id: "Item.1",
                title: "Recent",
                icon: Icons.clock,
                files: .init(NT_DesignToolFile.example.prefix(6))
            ),
            .init(
                id: "Item.2",
                title: "Pinned",
                icon: Icons.pin,
                files: NT_DesignToolFile.example.suffix(4)
            )
        ]
    }
}
