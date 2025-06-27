//
//  NT_Account.swift
//  Native
//

import Foundation

struct NT_Account {
    
    // MARK: - Properties:
    
    /// Identifier of the account:
    let id: String
    
    /// Name of the account:
    let name: String
    
    /// Description of the account:
    let description: String
    
    /// Username of the account:
    let username: String
    
    /// Image of the account:
    let image: String
    
    init(
        id: String,
        name: String,
        description: String,
        username: String,
        image: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.name = name
        self.description = description
        self.username = username
        self.image = image
    }
}

// MARK: - Identifiable:

extension NT_Account: Identifiable {  }

// MARK: - Equatable:

extension NT_Account: Equatable {  }

// MARK: - Hashable:

extension NT_Account: Hashable {  }

// MARK: - Example:

extension NT_Account {
    
    // MARK: - Computed properties:
    
    /// An array of the example accounts:
    static var example: [NT_Account] {
        [
            .init(
                id: "Item.1",
                name: "Amanda Clarke",
                description: "Photographer and Designer 📷",
                username: "@amanda",
                image: Images.main66
            ),
            .init(
                id: "Item.2",
                name: "Jessica Anderson",
                description: "Fashion and Travel 🏝️",
                username: "@jessica",
                image: Images.main67
            ),
            .init(
                id: "Item.3",
                name: "Tom Johnson",
                description: "Software Developer 💻",
                username: "@tom",
                image: Images.main68
            ),
            .init(
                id: "Item.4",
                name: "Jenny Poulson",
                description: "Photographer and Writer 📝",
                username: "@jenny",
                image: Images.main69
            ),
            .init(
                id: "Item.5",
                name: "James Phillips",
                description: "Digital Product Designer ✨",
                username: "@james",
                image: Images.main610
            )
        ]
    }
}
