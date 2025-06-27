//
//  NT_PhotoEditorSection.swift
//  Native
//

import Foundation

struct NT_PhotoEditorSection {
    
    // MARK: - Properties:
    
    /// Identifier of the section:
    let id: String
    
    /// Title of the section:
    let title: String
    
    /// 'Bool' value indicating whether or not the section is featured:
    let isFeatured: Bool
    
    /// An array of the photos that are part of the section:
    let photos: [NT_PhotoEditorPhoto]
    
    init(
        id: String,
        title: String,
        isFeatured: Bool,
        photos: [NT_PhotoEditorPhoto]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.isFeatured = isFeatured
        self.photos = photos
    }
}

// MARK: - Identifiable:

extension NT_PhotoEditorSection: Identifiable {  }

// MARK: - Equatable:

extension NT_PhotoEditorSection: Equatable {  }

// MARK: - Hashable:

extension NT_PhotoEditorSection: Hashable {  }

// MARK: - Example:

extension NT_PhotoEditorSection {
    
    // MARK: - Computed properties:
    
    /// An array of the example sections:
    static var example: [NT_PhotoEditorSection] {
        [
            .init(
                id: "Item.1",
                title: "Featured",
                isFeatured: true,
                photos: NT_PhotoEditorPhoto.example.filter { $0.section == "Item.1" }
            ),
            .init(
                id: "Item.2",
                title: "Latest",
                isFeatured: false,
                photos: NT_PhotoEditorPhoto.example.filter { $0.section == "Item.2" }
            )
        ]
    }
}
