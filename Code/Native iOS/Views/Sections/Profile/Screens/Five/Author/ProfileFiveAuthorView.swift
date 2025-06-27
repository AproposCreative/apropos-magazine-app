//
//  ProfileFiveAuthorView.swift
//  Native
//

import SwiftUI

struct ProfileFiveAuthorView: View {
    
    // MARK: - Properties:
    
    /// Author to display the details for:
    let author: NT_ProfileAuthor
    
    init(author: NT_ProfileAuthor) {
        
        /// Properties initialization:
        self.author = author
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .contentBackground()
    }
}

// MARK: - Item:

private extension ProfileFiveAuthorView {
    private var item: some View {
        VStack(
            alignment: .center,
            spacing: 12
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        authorContent
        subscribeButton
    }
}

// MARK: - Author:

private extension ProfileFiveAuthorView {
    private var authorContent: some View {
        AvatarTitleSubtitleView(
            avatarType: .image,
            avatarImage: image,
            avatarFrame: 64,
            avatarCornerRadius: 16,
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

// MARK: - Subscribe button:

private extension ProfileFiveAuthorView {
    private var subscribeButton: some View {
        ButtonView(
            title: subscribeTitle,
            titleFont: subscribeFont,
            titleAlignment: .leading,
            icon: subscribeIcon,
            iconFont: subscribeFont,
            style: .titleAndIcon,
            verticalPadding: subscribePadding,
            horizontalPadding: subscribePadding,
            cornerRadius: 10,
            action: subscribe
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProfileFiveAuthorView(author: .example)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
    .localizedNavigationTitle(title: "Profile")
    .navigationStack()
}
