//
//  MainSixPostsForYou+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainSixPostsForYouView {
    
    // MARK: - Functions:
    
    /// Returns the name of the account that the given post was posted by:
    func accountName(_ post: NT_Post) -> String {
        account(post).name
    }
    
    /// Returns the description of the given post:
    func description(_ post: NT_Post) -> String {
        post.description
    }
    
    /// Returns the time interval since the given post was posted as a string:
    func timeIntervalSincePosted(_ post: NT_Post) -> String {
        "\(post.timeIntervalSincePosted) ago"
    }
    
    /// Returns the title of the 'Bookmark' button that is based on whether or not the user has bookmarked the given post:
    func bookmarkTitle(_ post: NT_Post) -> String {
        isBookmarked(post) ? "Remove a Bookmark" : "Bookmark"
    }
    
    /// Returns the count of the likes that the given post currently has as a string:
    func likesCount(_ post: NT_Post) -> String {
        post.likesCount.formatted(.number.notation(.compactName))
    }
    
    /// Accessibility label of the 'Like' button of the given post:
    func likeAccessibilityLabel(_ post: NT_Post) -> LocalizedStringKey {
        isLiked(post) ? "Remove a Like" : "Like"
    }
    
    /// Returns the image of the given post:
    func image(_ post: NT_Post) -> Image {
        .init(post.image)
    }
    
    /// Returns the image of the account that the given post was posted by:
    func accountImage(_ post: NT_Post) -> Image {
        .init(account(post).image)
    }
    
    /// Returns the symbol variant of the icon of the 'Bookmark' button that is based on whether or not the user has bookmarked the given post:
    func bookmarkIconSymbolVariant(_ post: NT_Post) -> SymbolVariants {
        isBookmarked(post) ? .fill : .none
    }
    
    /// Returns the symbol variant of the icon of the 'Like' button that is based on whether or not the user has liked the given post:
    func likeIconSymbolVariant(_ post: NT_Post) -> SymbolVariants {
        isLiked(post) ? .fill : .none
    }
    
    /// Lets the user bookmark the given post:
    func bookmark(_ post: NT_Post) {
        
        /*
         
         NOTE: You can add your own logic for bookmarking the post here.
         
         */
        
    }
    
    /// Lets the user like the given post:
    func like(_ post: NT_Post) {
        
        /*
         
         NOTE: You can add your own logic for liking the post here.
         
         */
        
    }
    
    // MARK: - Private functions:
    
    /// Returns a 'Bool' value indicating whether or not the given post is currently bookmarked by the user:
    private func isBookmarked(_ post: NT_Post) -> Bool {
        post.isBookmarked
    }
    
    /// Returns a 'Bool' value indicating whether or not the given post is currently liked by the user:
    private func isLiked(_ post: NT_Post) -> Bool {
        post.isLiked
    }
    
    /// Returns the account that the given post was posted by:
    private func account(_ post: NT_Post) -> NT_Account {
        post.account
    }
}
