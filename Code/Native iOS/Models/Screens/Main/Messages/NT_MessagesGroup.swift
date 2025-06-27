//
//  NT_MessagesGroup.swift
//  Native
//

import SwiftUI

struct NT_MessagesGroup {
    
    // MARK: - Properties:
    
    /// Identifier of the group with the messages:
    let id: String
    
    /// Title of the group with the messages:
    let title: String
    
    /// Color of the group with the messages:
    let color: Color
    
    /// Starting color of the gradient of the group with the messages if applicable:
    let gradientStart: Color
    
    /// Ending color of the gradient of the group with the messages if applicable:
    let gradientEnd: Color
    
    /// Icon of the group with the messages:
    let icon: String
    
    /// An array of the messages that are part of the group with the messages:
    let messages: [NT_Message]
    
    init(
        id: String,
        title: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        icon: String,
        messages: [NT_Message]
    ) {
        
        /// Properties initialization:
        self.id = id
        self.title = title
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.icon = icon
        self.messages = messages
    }
}

// MARK: - Identifiable:

extension NT_MessagesGroup: Identifiable {  }

// MARK: - Equatable:

extension NT_MessagesGroup: Equatable {  }

// MARK: - Hashable:

extension NT_MessagesGroup: Hashable {  }

// MARK: - Example:

extension NT_MessagesGroup {
    
    // MARK: - Computed properties:
    
    /// An array of the example groups with the messages:
    static var example: [NT_MessagesGroup] {
        [
            .init(
                id: "Item.1",
                title: "Mexico Trip",
                color: .blue,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                icon: Icons.airplane,
                messages: .init(NT_Message.example.prefix(1))
            ),
            .init(
                id: "Item.2",
                title: "Web Design Project",
                color: .orange,
                gradientStart: .orangeGradientStart,
                gradientEnd: .orangeGradientEnd,
                icon: Icons.desktopcomputer,
                messages: NT_Message.example.filter {
                    $0.id == "Item.2"
                    || $0.id == "Item.3"
                    || $0.id == "Item.4"
                }
            ),
            .init(
                id: "Item.3",
                title: "The Best Team",
                color: .purple,
                gradientStart: .purpleGradientStart,
                gradientEnd: .purpleGradientEnd,
                icon: Icons.partyPopper,
                messages: .init(NT_Message.example.dropFirst().dropLast())
            )
        ]
    }
}
