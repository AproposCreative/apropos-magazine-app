//
//  MainFiveCommentsView.swift
//  Native
//

import SwiftUI

struct MainFiveCommentsView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the comments to display:
    let comments: [NT_Comment]
    
    init(comments: [NT_Comment]) {
        
        /// Properties initialization:
        self.comments = comments
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

private extension MainFiveCommentsView {
    private var item: some View {
        Section("Comments") {
            commentsContent
        }
    }
}

// MARK: - Comments:

private extension MainFiveCommentsView {
    private var commentsContent: some View {
        ForEach(
            comments,
            content: comment
        )
    }
    
    private func comment(_ comment: NT_Comment) -> some View {
        NavigationLink(value: comment) {
            commentLabel(comment)
        }
    }
    
    private func commentLabel(_ comment: NT_Comment) -> some View {
        AvatarTitleValueSubtitleView(
            avatarType: .image,
            avatarImage: image(comment),
            isShowingAvatarIndicator: !isRead(comment),
            avatarIndicatorBorderColor: avatarIndicatorBorderColor,
            avatarIndicatorAccessibilityLabel: avatarIndicatorAccessibilityLabel(comment),
            title: name(comment),
            titleLineLimit: titleLineLimit,
            value: timeIntervalSinceLeft(comment),
            subtitle: content(comment),
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
        MainFiveCommentsView(comments: NT_Comment.example)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Overview")
    .navigationDestination(for: NT_Comment.self) { comment in
        PlaceholderView(title: comment.content)
    }
    .navigationStack()
}
