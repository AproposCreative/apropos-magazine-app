//
//  NT_BlogArticle.swift
//  Native
//

import Foundation

struct NT_BlogArticle {
    
    // MARK: - Properties:
    
    /// Identifier of the article:
    let id: String
    
    /// Title of the article:
    let title: String
    
    /// Category of the article:
    let category: String
    
    /// Description of the article:
    let description: String
    
    /// Image of the article:
    let image: String
    
    /// Full image of the article:
    let fullImage: String
    
    /// 'Bool' value indicating whether or not the article is bookmarked by the user:
    let isBookmarked: Bool
    
    /// 'Bool' value indicating whether or not the article is currently featured:
    let isFeatured: Bool
    
    /// Date when the article was published:
    let publishedDate: Date
    
    init(
        id: String,
        title: String,
        category: String,
        description: String,
        image: String,
        fullImage: String,
        isBookmarked: Bool,
        isFeatured: Bool,
        publishedDate: Date
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.category = category
        self.description = description
        self.image = image
        self.fullImage = fullImage
        self.isBookmarked = isBookmarked
        self.isFeatured = isFeatured
        self.publishedDate = publishedDate
    }
}

// MARK: - Identifiable:

extension NT_BlogArticle: Identifiable {  }

// MARK: - Equatable:

extension NT_BlogArticle: Equatable {  }

// MARK: - Hashable:

extension NT_BlogArticle: Hashable {  }

// MARK: - Example:

extension NT_BlogArticle {
    
    // MARK: - Computed properties:
    
    /// An array of the example articles:
    static var example: [NT_BlogArticle] {
        [
            .init(
                id: "Item.1",
                title: "Designing and Building Apps for Mobile and Desktop Platforms in 2024",
                category: "Software Development",
                description: "Everything you need to know to design and build your next app for both iOS and macOS platforms.",
                image: Images.main81,
                fullImage: Images.main82,
                isBookmarked: true,
                isFeatured: true,
                publishedDate: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 9,
                    withDay: 12,
                    withHour: 10,
                    withMinute: 30
                )
            ),
            .init(
                id: "Item.2",
                title: "Building Scalable Design System",
                category: "Product Design",
                description: "Everything you need to know to design and build your next app for both iOS and macOS platforms.",
                image: Images.main83,
                fullImage: Images.main84,
                isBookmarked: false,
                isFeatured: true,
                publishedDate: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 9,
                    withDay: 10,
                    withHour: 10,
                    withMinute: 30
                )
            ),
            .init(
                id: "Item.3",
                title: "Top 10 Marketing Strategies for Your Business",
                category: "Marketing",
                description: "Everything you need to know to design and build your next app for both iOS and macOS platforms.",
                image: Images.main85,
                fullImage: Images.main86,
                isBookmarked: false,
                isFeatured: false,
                publishedDate: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 9,
                    withDay: 8,
                    withHour: 8,
                    withMinute: 45
                )
            ),
            .init(
                id: "Item.4",
                title: "Improve the Performance of Your Mobile App",
                category: "Software Development",
                description: "Everything you need to know to design and build your next app for both iOS and macOS platforms.",
                image: Images.main87,
                fullImage: Images.main88,
                isBookmarked: false,
                isFeatured: false,
                publishedDate: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 9,
                    withDay: 6,
                    withHour: 11,
                    withMinute: 30
                )
            ),
            .init(
                id: "Item.5",
                title: "What to Consider When Refactoring Your Entire Codebase",
                category: "Software Development",
                description: "Everything you need to know to design and build your next app for both iOS and macOS platforms.",
                image: Images.main89,
                fullImage: Images.main810,
                isBookmarked: false,
                isFeatured: false,
                publishedDate: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 9,
                    withDay: 4,
                    withHour: 12,
                    withMinute: 0
                )
            ),
            .init(
                id: "Item.6",
                title: "All You Need to Become a UI Designer in 2024",
                category: "UI Design",
                description: "Everything you need to know to design and build your next app for both iOS and macOS platforms.",
                image: Images.main811,
                fullImage: Images.main812,
                isBookmarked: false,
                isFeatured: false,
                publishedDate: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 9,
                    withDay: 2,
                    withHour: 14,
                    withMinute: 25
                )
            ),
            .init(
                id: "Item.7",
                title: "Increase Your Downloads with These 5 Simple Email Marketing Ideas",
                category: "Marketing",
                description: "Everything you need to know to design and build your next app for both iOS and macOS platforms.",
                image: Images.main813,
                fullImage: Images.main814,
                isBookmarked: false,
                isFeatured: false,
                publishedDate: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 31,
                    withHour: 18,
                    withMinute: 45
                )
            ),
            .init(
                id: "Item.8",
                title: "How to Redesign Your Current Logo",
                category: "Brand Design",
                description: "Everything you need to know to design and build your next app for both iOS and macOS platforms.",
                image: Images.main815,
                fullImage: Images.main816,
                isBookmarked: false,
                isFeatured: false,
                publishedDate: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 29,
                    withHour: 15,
                    withMinute: 0
                )
            ),
            .init(
                id: "Item.9",
                title: "Top 5 Apps for Software Developers in 2024",
                category: "Apps and Tools",
                description: "Everything you need to know to design and build your next app for both iOS and macOS platforms.",
                image: Images.main817,
                fullImage: Images.main818,
                isBookmarked: false,
                isFeatured: false,
                publishedDate: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 27,
                    withHour: 20,
                    withMinute: 30
                )
            ),
            .init(
                id: "Item.10",
                title: "Simplify Your UX Process",
                category: "User Experience",
                description: "Everything you need to know to design and build your next app for both iOS and macOS platforms.",
                image: Images.main819,
                fullImage: Images.main820,
                isBookmarked: false,
                isFeatured: false,
                publishedDate: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 8,
                    withDay: 25,
                    withHour: 6,
                    withMinute: 45
                )
            )
        ]
    }
}
