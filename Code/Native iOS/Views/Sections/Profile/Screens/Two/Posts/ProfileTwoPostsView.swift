//
//  ProfileTwoPostsView.swift
//  Native
//

import SwiftUI

struct ProfileTwoPostsView: View {
    
    // MARK: - Properties:
    
    /// Type of the posts that is currently selected:
    @State var postType: NT_ProfileAccountPostType = .posts
    
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
        mainContent
            .onChange(
                of: postType,
                postTypeOnChange
            )
            .animation(
                .default,
                value: posts
            )
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension ProfileTwoPostsView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        postTypePicker
        postsContent
    }
}

// MARK: - Post type picker:

private extension ProfileTwoPostsView {
    private var postTypePicker: some View {
        postTypePickerContent
            .pickerStyle(.segmented)
            .labelsHidden()
    }
    
    private var postTypePickerContent: some View {
        Picker(
            "Post Type",
            selection: $postType
        ) {
            postTypesContent
        }
    }
    
    private var postTypesContent: some View {
        ForEach(
            postTypes,
            content: postType
        )
    }
    
    private func postType(_ type: NT_ProfileAccountPostType) -> some View {
        Text(title(type))
            .tag(type)
    }
}

// MARK: - Posts:

private extension ProfileTwoPostsView {
    private var postsContent: some View {
        postsItem
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Posts")
    }
    
    private var postsItem: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: postsSpacing
        ) {
            postsItemContent
        }
    }
    
    private var postsItemContent: some View {
        ForEach(
            posts,
            content: post
        )
    }
    
    private func post(_ post: NT_ProfilePost) -> some View {
        ImageBackgroundView(
            image: image(post),
            width: nil,
            height: 96,
            isShowingBackground: false,
            cornerRadius: 12
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProfileTwoPostsView(account: .example)
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
