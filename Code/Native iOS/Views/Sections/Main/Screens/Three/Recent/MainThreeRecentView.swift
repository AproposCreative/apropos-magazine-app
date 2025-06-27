//
//  MainThreeRecentView.swift
//  Native
//

import SwiftUI

struct MainThreeRecentView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the messages to display:
    let messages: [NT_Message]
    
    init(messages: [NT_Message]) {
        
        /// Properties initialization:
        self.messages = messages
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            mainContent
        }
    }
    
    private var mainContent: some View {
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension MainThreeRecentView {
    private var item: some View {
        Section("Recent") {
            messagesContent
        }
    }
}

// MARK: - Messages:

private extension MainThreeRecentView {
    private var messagesContent: some View {
        ForEach(
            messages,
            content: message
        )
    }
    
    private func message(_ message: NT_Message) -> some View {
        NavigationLink(value: message) {
            messageLabel(message)
        }
    }
    
    private func messageLabel(_ message: NT_Message) -> some View {
        AvatarTitleValueSubtitleView(
            avatarType: .image,
            avatarImage: image(message),
            isShowingAvatarIndicator: !isRead(message),
            avatarIndicatorBorderColor: avatarIndicatorBorderColor,
            avatarIndicatorAccessibilityLabel: avatarIndicatorAccessibilityLabel(message),
            title: name(message),
            titleLineLimit: titleLineLimit,
            value: timeIntervalSinceSent(message),
            subtitle: content(message),
            subtitleLineLimit: subtitleLineLimit,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        MainThreeRecentView(messages: NT_Message.example)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Messages")
    .navigationDestination(for: NT_Message.self) { message in
        PlaceholderView(title: message.content)
    }
    .navigationStack()
}
