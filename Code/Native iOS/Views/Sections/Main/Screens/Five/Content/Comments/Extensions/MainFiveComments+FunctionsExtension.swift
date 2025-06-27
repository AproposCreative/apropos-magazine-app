//
//  MainFiveComments+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainFiveCommentsView {
    
    // MARK: - Functions:
    
    /// Returns the name of the person who left the given comment:
    func name(_ comment: NT_Comment) -> String {
        comment.name
    }
    
    /// Returns the content of the given comment:
    func content(_ comment: NT_Comment) -> String {
        comment.content
    }
    
    /// Returns the time interval since the given comment was left as a string:
    func timeIntervalSinceLeft(_ comment: NT_Comment) -> String {
        "\(comment.timeIntervalSinceLeft) ago"
    }
    
    /// Accessibility label of the indicator of the avatar of the given comment that is based on whether or not the user has already read the given comment:
    func avatarIndicatorAccessibilityLabel(_ comment: NT_Comment) -> String {
        isRead(comment) ? "" : "Unread"
    }
    
    /// Returns the image of the person who left the given comment:
    func image(_ comment: NT_Comment) -> Image {
        .init(comment.image)
    }
    
    /// Returns a 'Bool' value indicating whether or not the user has read the given comment:
    func isRead(_ comment: NT_Comment) -> Bool {
        comment.isRead
    }
}
