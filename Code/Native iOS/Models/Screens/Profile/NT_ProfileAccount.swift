//
//  NT_ProfileAccount.swift
//  Native
//

import Foundation

struct NT_ProfileAccount {
    
    // MARK: - Properties:
    
    /// Identifier of the account:
    let id: String
    
    /// Name of the account:
    let name: String
    
    /// Username of the account:
    let username: String
    
    /// Image of the account:
    let image: String
    
    /// 'Bool' value indicating whether or not the user is following the account:
    let isFollowing: Bool
    
    /// An array of the stats of the account:
    let stats: [NT_ProfileAccountStat]
    
    /// An array of the posts of the account:
    let posts: [NT_ProfilePost]
    
    init(
        id: String,
        name: String,
        username: String,
        image: String,
        isFollowing: Bool,
        stats: [NT_ProfileAccountStat],
        posts: [NT_ProfilePost]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.name = name
        self.username = username
        self.image = image
        self.isFollowing = isFollowing
        self.stats = stats
        self.posts = posts
    }
}

// MARK: - Identifiable:

extension NT_ProfileAccount: Identifiable {  }

// MARK: - Equatable:

extension NT_ProfileAccount: Equatable {  }

// MARK: - Hashable:

extension NT_ProfileAccount: Hashable {  }

// MARK: - Example:

extension NT_ProfileAccount {
    
    // MARK: - Computed properties:
    
    /// Example of the account:
    static var example: NT_ProfileAccount {
        .init(
            id: "Account",
            name: "John Smith",
            username: "@john.smith_123",
            image: Images.profile21,
            isFollowing: true,
            stats: NT_ProfileAccountStat.example,
            posts: NT_ProfilePost.example
        )
    }
}
