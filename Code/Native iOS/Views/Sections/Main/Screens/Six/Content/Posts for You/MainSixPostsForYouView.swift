//
//  MainSixPostsForYouView.swift
//  Native
//

import SwiftUI

struct MainSixPostsForYouView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the posts to display:
    let posts: [NT_Post]
    
    init(posts: [NT_Post]) {
        
        /// Properties initialization:
        self.posts = posts
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

private extension MainSixPostsForYouView {
    private var item: some View {
        Section("Posts for You") {
            postsContent
        }
    }
}

// MARK: - Posts:

private extension MainSixPostsForYouView {
    private var postsContent: some View {
        ForEach(
            posts,
            content: post
        )
    }
    
    private func post(_ post: NT_Post) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            postContent(post)
        }
    }
    
    @ViewBuilder
    private func postContent(_ post: NT_Post) -> some View {
        postImage(post)
        postAccount(post)
    }
    
    private func postImage(_ post: NT_Post) -> some View {
        postImageContent(post)
            .accessibilityElement(children: .ignore)
            .overlay(alignment: .topLeading) {
                postBookmarkButton(post)
            }
            .overlay(alignment: .topTrailing) {
                postLikeButton(post)
            }
            .buttonStyle(.plain)
            .darkColorScheme()
    }
    
    private func postImageContent(_ post: NT_Post) -> some View {
        ImageBackgroundView(
            image: image(post),
            height: 224,
            cornerRadius: 16
        )
    }
    
    private func postBookmarkButton(_ post: NT_Post) -> some View {
        postBookmarkButtonContent(post)
            .padding(buttonPadding)
    }
    
    private func postBookmarkButtonContent(_ post: NT_Post) -> some View {
        ButtonView(
            title: bookmarkTitle(post),
            icon: Icons.bookmark,
            iconSymbolVariant: bookmarkIconSymbolVariant(post),
            iconFont: .body,
            iconColor: buttonColor,
            iconFrame: bookmarkIconFrame,
            style: .iconOnly,
            verticalPadding: bookmarkPadding,
            horizontalPadding: bookmarkPadding,
            isFullWidth: false,
            backgroundColor: buttonBackgroundColor,
            isBackgroundColorGradient: false,
            cornerRadius: 16
        ) {
            bookmark(post)
        }
    }
    
    private func postLikeButton(_ post: NT_Post) -> some View {
        postLikeButtonContent(post)
            .padding(buttonPadding)
            .accessibilityLabel(likeAccessibilityLabel(post))
    }
    
    private func postLikeButtonContent(_ post: NT_Post) -> some View {
        ButtonView(
            title: likesCount(post),
            titleFont: .footnote.bold(),
            titleColor: buttonColor,
            icon: Icons.heart,
            iconSymbolVariant: likeIconSymbolVariant(post),
            iconFont: likeIconFont,
            iconGradientStart: .redGradientStart,
            iconGradientEnd: .redGradientEnd,
            isIconColorGradient: true,
            iconFrame: 16,
            style: .titleAndIcon,
            verticalPadding: 4,
            horizontalPadding: 8,
            isFullWidth: false,
            backgroundColor: buttonBackgroundColor,
            isBackgroundColorGradient: false,
            cornerRadius: 8
        ) {
            like(post)
        }
    }
    
    private func postAccount(_ post: NT_Post) -> some View {
        AvatarTitleValueSubtitleView(
            avatarType: .image,
            avatarImage: accountImage(post),
            avatarFrame: 36,
            avatarCornerRadius: 18,
            title: accountName(post),
            value: timeIntervalSincePosted(post),
            subtitle: description(post),
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
        MainSixPostsForYouView(posts: NT_Post.example)
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Recent")
    .navigationStack()
}
