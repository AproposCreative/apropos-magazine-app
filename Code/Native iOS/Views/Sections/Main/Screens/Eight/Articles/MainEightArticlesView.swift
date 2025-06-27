//
//  MainEightArticlesView.swift
//  Native
//

import SwiftUI

struct MainEightArticlesView: View {
    
    // MARK: - Properties:
    
    /// An array of the articles to display:
    let articles: [NT_BlogArticle]
    
    init(articles: [NT_BlogArticle]) {
        
        /// Properties initialization:
        self.articles = articles
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

private extension MainEightArticlesView {
    private var item: some View {
        Section("Popular Articles") {
            articlesContent
        }
    }
}

// MARK: - Articles:

private extension MainEightArticlesView {
    private var articlesContent: some View {
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
        ImageBackgroundTitleSubtitleView(
            image: image(article),
            imageWidth: imageFrame,
            imageHeight: imageFrame,
            isImageFullWidth: false,
            imageCornerRadius: 8,
            title: title(article),
            titleFont: .headline,
            titleAlignment: .leading,
            subtitle: category(article),
            subtitleFont: .subheadline,
            subtitleAlignment: .leading,
            titleSubtitleAlignment: .leading,
            titleSubtitleSpacing: 4,
            titleSubtitleMaxWidthAlignment: .leading,
            alignment: .horizontal,
            horizontalAlignment: .leading,
            spacing: 12
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        MainEightArticlesView(articles: NT_BlogArticle.example)
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Blog")
    .navigationDestination(for: NT_BlogArticle.self) { article in
        PlaceholderView(title: article.title)
    }
    .navigationStack()
}
