//
//  NT_Post.swift
//  Native
//

import Foundation

struct NT_Post {
    
    // MARK: - Properties:
    
    /// Identifier of the post:
    let id: String
    
    /// Description of the post:
    let description: String
    
    /// Date when the post was posted:
    let date: Date
    
    /// Image of the post:
    let image: String
    
    /// 'Bool' value indicating whether or not the post is currently bookmarked by the user:
    let isBookmarked: Bool
    
    /// 'Bool' value indicating whether or not the post is currently liked by the user:
    let isLiked: Bool
    
    /// Count of the likes that the post currently has:
    let likesCount: Int
    
    /// Account that the post was posted by:
    let account: NT_Account
    
    init(
        id: String,
        description: String,
        date: Date,
        image: String,
        isBookmarked: Bool,
        isLiked: Bool,
        likesCount: Int,
        account: NT_Account
    ) {
        
        /// Properties initialization:
        self.id = id
        self.description = description
        self.date = date
        self.image = image
        self.isBookmarked = isBookmarked
        self.isLiked = isLiked
        self.likesCount = likesCount
        self.account = account
    }
    
    // MARK: - Computed properties:
    
    /// Time interval since the post was posted as a string:
    var timeIntervalSincePosted: String {
        if let timeInterval: String = Formatters.timeInterval(fromDate: date) {
            return timeInterval
        } else {
            return ""
        }
    }
}

// MARK: - Identifiable:

extension NT_Post: Identifiable {  }

// MARK: - Equatable:

extension NT_Post: Equatable {  }

// MARK: - Hashable:

extension NT_Post: Hashable {  }

// MARK: - Example:

extension NT_Post {
    
    // MARK: - Computed properties:
    
    /// An array of the example posts:
    static var example: [NT_Post] {
        [
            .init(
                id: "Item.1",
                description: "Yesterday I took one of my most favorite photos yet. Just take a look! 🌇",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 29,
                    withHour: 11,
                    withMinute: 25
                ),
                image: Images.main63,
                isBookmarked: true,
                isLiked: true,
                likesCount: 1219,
                account: NT_Account.example.first { $0.id == "Item.1" }!
            ),
            .init(
                id: "Item.2",
                description: "Here is the latest design that I have done. ✨ What do you think? I would highly appreciate your suggestions!",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 28,
                    withHour: 20,
                    withMinute: 45
                ),
                image: Images.main64,
                isBookmarked: false,
                isLiked: false,
                likesCount: 954,
                account: NT_Account.example.first { $0.id == "Item.2" }!
            ),
            .init(
                id: "Item.3",
                description: "Here is another one from my recent adventure. Do you like the photo? ⭐️",
                date: .dateWithComponents(
                    withYear: 2024,
                    withMonth: 7,
                    withDay: 26,
                    withHour: 16,
                    withMinute: 15
                ),
                image: Images.main65,
                isBookmarked: true,
                isLiked: false,
                likesCount: 7302,
                account: NT_Account.example.first { $0.id == "Item.3" }!
            )
        ]
    }
}
