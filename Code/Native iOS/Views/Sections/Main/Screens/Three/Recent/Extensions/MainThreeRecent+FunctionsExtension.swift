//
//  MainThreeRecent+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainThreeRecentView {
    
    // MARK: - Functions:
    
    /// Returns the name of the person who sent the given message:
    func name(_ message: NT_Message) -> String {
        message.name
    }
    
    /// Returns the content of the given message:
    func content(_ message: NT_Message) -> String {
        message.content
    }
    
    /// Returns the time interval since the given message was sent as a string:
    func timeIntervalSinceSent(_ message: NT_Message) -> String {
        "\(message.timeIntervalSinceSent) ago"
    }
    
    /// Accessibility label of the indicator of the avatar of the given message that is based on whether or not the user has already read the given message:
    func avatarIndicatorAccessibilityLabel(_ message: NT_Message) -> String {
        isRead(message) ? "" : "Unread"
    }
    
    /// Returns the image of the person who sent the given message:
    func image(_ message: NT_Message) -> Image {
        .init(message.image)
    }
    
    /// Returns a 'Bool' value indicating whether or not the user has read the given message:
    func isRead(_ message: NT_Message) -> Bool {
        message.isRead
    }
}
