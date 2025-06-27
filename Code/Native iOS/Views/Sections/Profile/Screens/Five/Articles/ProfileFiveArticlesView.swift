//
//  ProfileFiveArticlesView.swift
//  Native
//

import SwiftUI

struct ProfileFiveArticlesView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// Type of the articles that is currently selected:
    @State var articleType: NT_ProfileAuthorArticleType = .latest
    
    /// Author to display the articles for:
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
            .onChange(
                of: articleType,
                articleTypeOnChange
            )
            .animation(
                .default,
                value: articles
            )
    }
}

// MARK: - Item:

private extension ProfileFiveArticlesView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        header
        articlesContent
    }
}

// MARK: - Header:

private extension ProfileFiveArticlesView {
    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            headerContent
        }
    }
    
    @ViewBuilder
    private var headerContent: some View {
        SectionHeaderView(title: "Articles")
        articleTypePicker
    }
}

// MARK: - Article type picker:

private extension ProfileFiveArticlesView {
    private var articleTypePicker: some View {
        articleTypePickerContent
            .pickerStyle(.segmented)
            .labelsHidden()
    }
    
    private var articleTypePickerContent: some View {
        Picker(
            "Article Type",
            selection: $articleType
        ) {
            articleTypesContent
        }
    }
    
    private var articleTypesContent: some View {
        ForEach(
            articleTypes,
            content: articleType
        )
    }
    
    private func articleType(_ type: NT_ProfileAuthorArticleType) -> some View {
        Text(title(type))
            .tag(type)
    }
}

// MARK: - Articles:

private extension ProfileFiveArticlesView {
    @ViewBuilder
    private var articlesContent: some View {
        if isShowing {
            articlesItem
        }
    }
    
    private var articlesItem: some View {
        LazyVStack(
            alignment: .leading,
            spacing: spacing
        ) {
            articlesItemContent
        }
    }
    
    private var articlesItemContent: some View {
        ForEach(
            articles,
            content: article
        )
    }
    
    private func article(_ article: NT_BlogArticle) -> some View {
        NavigationLink(value: article) {
            articleLabel(article)
        }
    }
    
    private func articleLabel(_ article: NT_BlogArticle) -> some View {
        ImageBackgroundTitleSubtitleIconView(
            image: image(article),
            title: title(article),
            subtitle: category(article),
            iconFrame: iconFrame
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ProfileFiveArticlesView(author: .example)
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
    .navigationDestination(for: NT_BlogArticle.self) { article in
        PlaceholderView(title: article.title)
    }
    .navigationStack()
}
