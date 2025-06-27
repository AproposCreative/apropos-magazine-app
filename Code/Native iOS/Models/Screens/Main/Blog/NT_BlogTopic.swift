//
//  NT_BlogTopic.swift
//  Native
//

import SwiftUI

struct NT_BlogTopic {
    
    // MARK: - Properties:
    
    /// Identifier of the topic:
    let id: String
    
    /// Title of the topic:
    let title: String
    
    /// Color of the topic:
    let color: Color
    
    /// Starting color of the gradient of the topic:
    let gradientStart: Color
    
    /// Ending color of the gradient of the topic:
    let gradientEnd: Color
    
    /// Icon of the topic:
    let icon: String
    
    /// An array of the articles that are part of the topic:
    let articles: [NT_BlogArticle]
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String,
        articles: [NT_BlogArticle]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
        self.articles = articles
    }
    
    // MARK: - Computed properties:
    
    /// Count of the articles that are part of the topic:
    var articlesCount: Int {
        articles.count
    }
}

// MARK: - Identifiable:

extension NT_BlogTopic: Identifiable {  }

// MARK: - Equatable:

extension NT_BlogTopic: Equatable {  }

// MARK: - Hashable:

extension NT_BlogTopic: Hashable {  }

// MARK: - Example:

extension NT_BlogTopic {
    
    // MARK: - Computed properties:
    
    /// An array of the example topics:
    static var example: [NT_BlogTopic] {
        [
            .init(
                id: "Item.1",
                title: "Software Development",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.chevronLeftForwardslashChevronRight,
                articles: .init(NT_BlogArticle.example.prefix(8))
            ),
            .init(
                id: "Item.2",
                title: "Product Design",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.sparkles,
                articles: .init(NT_BlogArticle.example.prefix(6))
            ),
            .init(
                id: "Item.3",
                title: "Marketing",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.megaphone,
                articles: .init(NT_BlogArticle.example.prefix(5))
            ),
            .init(
                id: "Item.4",
                title: "UI Design",
                color: .pink,
                gradientStart: .pinkGradientStart,
                gradientEnd: .pinkGradientEnd,
                icon: Icons.rectangleStack,
                articles: .init(NT_BlogArticle.example.prefix(2))
            ),
            .init(
                id: "Item.5",
                title: "Brand Design",
                color: .green,
                gradientStart: .greenGradientStart,
                gradientEnd: .greenGradientEnd,
                icon: Icons.paintbrush,
                articles: .init(NT_BlogArticle.example.prefix(1))
            ),
            .init(
                id: "Item.6",
                title: "Apps and Tools",
                color: .gray,
                gradientStart: .grayGradientStart,
                gradientEnd: .grayGradientEnd,
                icon: Icons.hammer,
                articles: NT_BlogArticle.example
            ),
            .init(
                id: "Item.7",
                title: "User Experience",
                color: .indigo,
                gradientStart: .indigoGradientStart,
                gradientEnd: .indigoGradientEnd,
                icon: Icons.person,
                articles: .init(NT_BlogArticle.example.prefix(4))
            )
        ]
    }
}
