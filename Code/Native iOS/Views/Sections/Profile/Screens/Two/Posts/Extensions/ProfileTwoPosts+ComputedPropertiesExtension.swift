//
//  ProfileTwoPosts+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension ProfileTwoPostsView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !posts.isEmpty
    }
    
    /// An array of the types of the posts to select from:
    var postTypes: [NT_ProfileAccountPostType] {
        NT_ProfileAccountPostType.allCases
    }
    
    /// An array of the posts to display:
    var posts: [NT_ProfilePost] {
        posts(postType)
    }
    
    /// An array of the columns to display the posts in the grid:
    var columns: [GridItem] {
        [
            .init(
                .adaptive(
                    minimum: 96,
                    maximum: 144
                ),
                spacing: postsSpacing,
                alignment: .topLeading
            )
        ]
    }
    
    /// Spacing between the posts:
    var postsSpacing: Double {
        8
    }
}
