//
//  ProfileTwoAccountView.swift
//  Native
//

import SwiftUI

struct ProfileTwoAccountView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// Account to display the details for:
    let account: NT_ProfileAccount
    
    init(account: NT_ProfileAccount) {
        
        /// Properties initialization:
        self.account = account
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        VStack(
            alignment: .center,
            spacing: 24
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension ProfileTwoAccountView {
    @ViewBuilder
    private var item: some View {
        user
        statsContent
        buttons
    }
}

// MARK: - User:

private extension ProfileTwoAccountView {
    private var user: some View {
        AvatarTitleSubtitleView(
            avatarType: .image,
            avatarImage: image,
            avatarFrame: 96,
            avatarCornerRadius: 48,
            title: name,
            titleAlignment: .center,
            subtitle: username,
            subtitleAlignment: .center,
            titleSubtitleAlignment: .center,
            titleSubtitleMaxWidthAlignment: .center,
            alignment: .vertical,
            horizontalAlignment: .center,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Stats:

private extension ProfileTwoAccountView {
    private var statsContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .center,
            spacing: statsSpacing
        ) {
            statsItem
        }
    }
    
    private var statsItem: some View {
        ForEach(
            stats,
            content: stat
        )
    }
    
    private func stat(_ stat: NT_ProfileAccountStat) -> some View {
        TitleSubtitleView(
            title: value(stat),
            titleFont: .subheadline.bold(),
            titleAlignment: .center,
            subtitle: title(stat),
            subtitleFont: .footnote,
            subtitleAlignment: .center,
            alignment: .center,
            spacing: 2,
            maxWidth: .infinity,
            maxWidthAlignment: .center,
            verticalPadding: statPadding,
            horizontalPadding: statPadding,
            maxHeight: .infinity,
            isShowingBackground: true,
            backgroundColor: backgroundColor,
            cornerRadius: 12
        )
    }
}

// MARK: - Buttons:

private extension ProfileTwoAccountView {
    @ViewBuilder
    private var buttons: some View {
        if shouldMoveContent {
            verticalButtonsContent
        } else {
            horizontalButtonsContent
        }
    }
    
    private var horizontalButtonsContent: some View {
        HStack(
            alignment: .top,
            spacing: buttonsSpacing
        ) {
            buttonsItem
        }
    }
    
    private var verticalButtonsContent: some View {
        VStack(
            alignment: .leading,
            spacing: buttonsSpacing
        ) {
            buttonsItem
        }
    }
    
    @ViewBuilder
    private var buttonsItem: some View {
        followButton
        messageButton
    }
    
    private var followButton: some View {
        ButtonView(
            title: followTitle,
            titleAlignment: buttonTitleAlignment,
            icon: followIcon,
            style: buttonStyle,
            action: follow
        )
    }
    
    private var messageButton: some View {
        ButtonView(
            title: "Message",
            titleAlignment: buttonTitleAlignment,
            titleColor: .primary,
            icon: Icons.textBubble,
            iconColor: .init(.tertiaryLabel),
            style: buttonStyle,
            backgroundColor: backgroundColor,
            isBackgroundColorGradient: false,
            action: message
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProfileTwoAccountView(account: .example)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "Profile")
    .navigationStack()
}
