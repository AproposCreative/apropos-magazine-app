//
//  ProfileTwoPosts+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension ProfileTwoPostsView {
    
    // MARK: - Functions:
    
    /// Returns an array of the posts that are based on the given type:
    func posts(_ type: NT_ProfileAccountPostType) -> [NT_ProfilePost] {
        switch type {
        case .posts:
            return account.posts
        case .likes:
            return .init(account.posts.prefix(3))
        case .comments:
            return .init(account.posts.prefix(6))
        }
    }
    
    /// Returns the title of the given type of the posts:
    func title(_ type: NT_ProfileAccountPostType) -> String {
        type.title + " " + "(\(posts(type).count))"
    }
    
    /// Returns the image of the given post:
    func image(_ post: NT_ProfilePost) -> Image {
        .init(post.image)
    }
    
    /// Method that gets called whenever the type of the articles changes:
    func postTypeOnChange(
        _ previousType: NT_ProfileAccountPostType,
        _ newType: NT_ProfileAccountPostType
    ) {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change:
        HapticFeedbacks.selectionChanged()
    }
}
