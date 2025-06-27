//
//  NT_TermsOverview.swift
//  Native
//

import Foundation

struct NT_TermsOverview {
    
    // MARK: - Properties:
    
    /// Identifier of the overview item:
    let id: String
    
    /// Title of the overview item:
    let title: String
    
    /// Value of the overview item:
    let value: String
    
    /// Icon of the overview item:
    let icon: String
    
    /// URL of the overview item if applicable:
    let url: URL?
    
    init(
        id: String,
        title: String,
        value: String,
        icon: String,
        url: URL?
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.value = value
        self.icon = icon
        self.url = url
    }
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the overview item has a URL:
    var doesHaveURL: Bool {
        url != nil
    }
}

// MARK: - Identifiable:

extension NT_TermsOverview: Identifiable {  }

// MARK: - Equatable:

extension NT_TermsOverview: Equatable {  }

// MARK: - Hashable:

extension NT_TermsOverview: Hashable {  }

// MARK: - Example:

extension NT_TermsOverview {
    
    // MARK: - Computed properties:
    
    /// An array of the example overview items:
    static var example: [NT_TermsOverview] {
        [
            .init(
                id: "Item.1",
                title: "Last Updated",
                value: "19th July 2024",
                icon: Icons.calendar,
                url: nil
            ),
            .init(
                id: "Item.2",
                title: "Phone Number",
                value: "+1 234 567 890",
                icon: Icons.phone,
                url: URL(string: "tel:+1 234 567 890")
            ),
            .init(
                id: "Item.3",
                title: "Email Address",
                value: "info@applayouts.com",
                icon: Icons.envelope,
                url: URL(string: "mailto:info@applayouts.com?Native iOS")
            )
        ]
    }
}
