//
//  NT_PhotoEditorCategory.swift
//  Native
//

import Foundation

struct NT_PhotoEditorCategory {
    
    // MARK: - Properties:
    
    /// Identifier of the category:
    let id: String
    
    /// Title of the category:
    let title: String
    
    /// Icon of the category:
    let icon: String
    
    /// An array of the sections that are part of the category:
    let sections: [NT_PhotoEditorSection]
    
    init(
        id: String,
        title: String,
        icon: String,
        sections: [NT_PhotoEditorSection]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.icon = icon
        self.sections = sections
    }
}

// MARK: - Identifiable:

extension NT_PhotoEditorCategory: Identifiable {  }

// MARK: - Equatable:

extension NT_PhotoEditorCategory: Equatable {  }

// MARK: - Hashable:

extension NT_PhotoEditorCategory: Hashable {  }

// MARK: - Example:

extension NT_PhotoEditorCategory {
    
    // MARK: - Computed properties:
    
    /// An array of the example categories:
    static var example: [NT_PhotoEditorCategory] {
        [
            .init(
                id: "Item.1",
                title: "Early Morning",
                icon: Icons.sunMax,
                sections: NT_PhotoEditorSection.example
            ),
            .init(
                id: "Item.2",
                title: "Dark Sky",
                icon: Icons.cloud,
                sections: NT_PhotoEditorSection.example
            ),
            .init(
                id: "Item.3",
                title: "Sunset",
                icon: Icons.sunset,
                sections: NT_PhotoEditorSection.example
            ),
            .init(
                id: "Item.4",
                title: "Abstract",
                icon: Icons.rectangleThreeGroup,
                sections: NT_PhotoEditorSection.example
            ),
            .init(
                id: "Item.5",
                title: "Futuristic",
                icon: Icons.wind,
                sections: NT_PhotoEditorSection.example
            ),
            .init(
                id: "Item.6",
                title: "Sunrise",
                icon: Icons.sunrise,
                sections: NT_PhotoEditorSection.example
            ),
            .init(
                id: "Item.7",
                title: "Modern City",
                icon: Icons.buildingTwo,
                sections: NT_PhotoEditorSection.example
            ),
            .init(
                id: "Item.8",
                title: "Late Night",
                icon: Icons.moon,
                sections: NT_PhotoEditorSection.example
            ),
            .init(
                id: "Item.9",
                title: "Style",
                icon: Icons.sparkles,
                sections: NT_PhotoEditorSection.example
            ),
            .init(
                id: "Item.10",
                title: "Inspiring",
                icon: Icons.star,
                sections: NT_PhotoEditorSection.example
            )
        ]
    }
}
