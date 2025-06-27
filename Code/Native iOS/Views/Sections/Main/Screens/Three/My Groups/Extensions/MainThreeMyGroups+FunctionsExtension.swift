//
//  MainThreeMyGroups+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainThreeMyGroupsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given group with the messages:
    func title(_ group: NT_MessagesGroup) -> String {
        group.title
    }
    
    /// Returns the content of the latest message that is a part of the given group with the messages:
    func latestMessageContent(_ group: NT_MessagesGroup) -> String {
        group.messages.last?.content ?? "No messages"
    }
    
    /// Returns the time interval since the latest message that is a part of the given group with the messages was sent:
    func latestMessageTimeIntervalSinceSent(_ group: NT_MessagesGroup) -> String {
        if let timeIntervalSinceSent: String = group.messages.last?.timeIntervalSinceSent {
            return "\(timeIntervalSinceSent) ago"
        } else {
            return ""
        }
    }
    
    /// Accessibility label of the indicator of the avatar of the given group with the messages that is based on whether or not the user has already read all of the messages that are part of the given group with the messages:
    func avatarIndicatorAccessibilityLabel(_ group: NT_MessagesGroup) -> String {
        isRead(group) ? "" : "Unread"
    }
    
    /// Returns the color of the given group with the messages:
    func color(_ group: NT_MessagesGroup) -> Color {
        .init(group.color)
    }
    
    /// Returns the starting color of the gradient of the given group with the messages:
    func gradientStart(_ group: NT_MessagesGroup) -> Color {
        .init(group.gradientStart)
    }
    
    /// Returns the ending color of the gradient of the given group with the messages:
    func gradientEnd(_ group: NT_MessagesGroup) -> Color {
        .init(group.gradientEnd)
    }
    
    /// Returns the icon of the given group with the messages:
    func icon(_ group: NT_MessagesGroup) -> String {
        group.icon
    }
    
    /// Returns a 'Bool' value indicating whether or not the user has read all of the messages that are part of the given group with the messages:
    func isRead(_ group: NT_MessagesGroup) -> Bool {
        group.messages.allSatisfy { $0.isRead }
    }
}
