//
//  NT_TermsSubSection.swift
//  Native
//

import Foundation

struct NT_TermsSubsection {
    
    // MARK: - Properties:
    
    /// Identifier of the sub-section:
    let id: String
    
    /// Title of the sub-section:
    let title: String
    
    /// Content of the sub-section:
    let content: String
    
    init(
        id: String,
        title: String,
        content: String
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.content = content
    }
}

// MARK: - Identifiable:

extension NT_TermsSubsection: Identifiable {  }

// MARK: - Equatable:

extension NT_TermsSubsection: Equatable {  }

// MARK: - Hashable:

extension NT_TermsSubsection: Hashable {  }

// MARK: - Example:

extension NT_TermsSubsection {
    
    // MARK: - Computed properties:
    
    /// An array of the example sub-sections:
    static var example: [NT_TermsSubsection] {
        [
            .init(
                id: "Item.1",
                title: "1.1 Overview",
                content: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
            ),
            .init(
                id: "Item.2",
                title: "1.2 Acceptance of Terms",
                content: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
            ),
            .init(
                id: "Item.3",
                title: "1.3 Changes to Terms",
                content: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
            ),
            .init(
                id: "Item.4",
                title: "1.4 Contact Information",
                content: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. In arcu cursus euismod quis viverra nibh cras. Turpis cursus in hac habitasse. Sapien faucibus et molestie ac feugiat. Congue quisque egestas diam in arcu cursus euismod quis."
            ),
            .init(
                id: "Item.5",
                title: "1.5 Definitions",
                content: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. In arcu cursus euismod quis viverra nibh cras. Turpis cursus in hac habitasse. Sapien faucibus et molestie ac feugiat. Congue quisque egestas diam in arcu cursus euismod quis."
            )
        ]
    }
}
