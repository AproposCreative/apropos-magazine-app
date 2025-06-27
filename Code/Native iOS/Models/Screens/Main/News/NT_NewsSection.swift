//
//  NT_NewsSection.swift
//  Native
//

import Foundation

struct NT_NewsSection {
    
    // MARK: - Properties:
    
    /// Identifier of the section with the news:
    let id: String
    
    /// An array of the articles that are part of the given section with the news:
    let articles: [NT_NewsArticle]
    
    init(
        id: String,
        articles: [NT_NewsArticle]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.articles = articles
    }
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the given section with the news displays the articles that were published today:
    var isToday: Bool {
        articles.contains { $0.isToday }
    }
}

// MARK: - Identifiable:

extension NT_NewsSection: Identifiable {  }

// MARK: - Equatable:

extension NT_NewsSection: Equatable {  }

// MARK: - Hashable:

extension NT_NewsSection: Hashable {  }

// MARK: - Example:

extension NT_NewsSection {
    
    // MARK: - Computed properties:
    
    /// An array of the example sections with the news:
    static var example: [NT_NewsSection] {
        [
            .init(
                id: "Item.1",
                articles: NT_NewsArticle.example.filter { $0.isToday }
            ),
            .init(
                id: "Item.2",
                articles: NT_NewsArticle.example.filter { !$0.isToday }
            )
        ]
    }
}
