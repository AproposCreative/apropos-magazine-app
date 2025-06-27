//
//  NT_NewsArticle.swift
//  Native
//

import Foundation

struct NT_NewsArticle {
    
    // MARK: - Properties:
    
    /// Identifier of the article:
    let id: String
    
    /// Title of the article:
    let title: String
    
    /// Subtitle of the article:
    let subtitle: String
    
    /// Image of the article:
    let image: String
    
    /// Date when the article was published:
    let date: Date
    
    init(
        id: String,
        title: String,
        subtitle: String,
        image: String,
        date: Date
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.date = date
    }
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the article was published today:
    var isToday: Bool {
        date.isToday
    }
}

// MARK: - Identifiable:

extension NT_NewsArticle: Identifiable {  }

// MARK: - Equatable:

extension NT_NewsArticle: Equatable {  }

// MARK: - Hashable:

extension NT_NewsArticle: Hashable {  }

// MARK: - Example:

extension NT_NewsArticle {
    
    // MARK: - Computed properties:
    
    /// An array of the example articles:
    static var example: [NT_NewsArticle] {
        [
            .init(
                id: "Item.1",
                title: "Top 10 Best Tech Companies to Work for in 2024",
                subtitle: "Tech & Career",
                image: Images.main41,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 30
                )
            ),
            .init(
                id: "Item.2",
                title: "Check Out These Amazing Desk Setups Shared by Others",
                subtitle: "Workspace",
                image: Images.main42,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 29
                )
            ),
            .init(
                id: "Item.3",
                title: "Top 5 Skills to Master in 2024 to Get a Better Paying Job",
                subtitle: "Career",
                image: Images.main43,
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 29
                )
            )
        ]
    }
}
