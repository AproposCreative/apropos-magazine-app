//
//  NT_ProfileAuthor.swift
//  Native
//

import Foundation

struct NT_ProfileAuthor {
    
    // MARK: - Properties:
    
    /// Identifier of the author:
    let id: String
    
    /// Name of the author:
    let name: String
    
    /// Username of the author:
    let username: String
    
    /// Image of the author:
    let image: String
    
    /// 'Bool' value indicating whether or not the user is subscribed to the author:
    let isSubscribed: Bool
    
    /// An array of the overview items of the author:
    let overviewItem: [NT_ProfileAuthorOverview]
    
    /// An array of the articles of the author:
    let articles: [NT_BlogArticle]
    
    init(
        id: String,
        name: String,
        username: String,
        image: String,
        isSubscribed: Bool,
        overviewItem: [NT_ProfileAuthorOverview],
        articles: [NT_BlogArticle]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.name = name
        self.username = username
        self.image = image
        self.isSubscribed = isSubscribed
        self.overviewItem = overviewItem
        self.articles = articles
    }
}

// MARK: - Identifiable:

extension NT_ProfileAuthor: Identifiable {  }

// MARK: - Equatable:

extension NT_ProfileAuthor: Equatable {  }

// MARK: - Hashable:

extension NT_ProfileAuthor: Hashable {  }

// MARK: - Example:

extension NT_ProfileAuthor {
    
    // MARK: - Computed properties:
    
    /// Example of the author:
    static var example: NT_ProfileAuthor {
        .init(
            id: "Author",
            name: "John Smith",
            username: "@john.smith_123",
            image: Images.profile51,
            isSubscribed: false,
            overviewItem: NT_ProfileAuthorOverview.example,
            articles: NT_BlogArticle.example
        )
    }
}
