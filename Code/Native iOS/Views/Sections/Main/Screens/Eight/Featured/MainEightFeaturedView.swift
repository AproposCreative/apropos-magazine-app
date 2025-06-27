//
//  MainEightFeaturedView.swift
//  Native
//

import SwiftUI

struct MainEightFeaturedView: View {
    
    // MARK: - Properties:
    
    /// Horizontal size class of the device that the app is running on:
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the articles to display:
    let articles: [NT_BlogArticle]
    
    // MARK: - Private properties:
    
    /// Article that is currently shown:
    @Binding private var currentArticle: NT_BlogArticle?
    
    init(
        articles: [NT_BlogArticle],
        currentArticle: Binding<NT_BlogArticle?>
    ) {
        
        /// Properties initialization:
        self.articles = articles
        _currentArticle = currentArticle
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
            .listRowInsets(.init(.zero))
            .padding(
                .vertical,
                12
            )
            .padding(
                .horizontal,
                16
            )
    }
}

// MARK: - Item:

private extension MainEightFeaturedView {
    private var item: some View {
        VStack(
            alignment: .center,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        scroll
        pagination
    }
}

// MARK: - Scroll:

private extension MainEightFeaturedView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentArticle)
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        articlesContent
            .scrollTargetLayout()
    }
}

// MARK: - Articles:

private extension MainEightFeaturedView {
    private var articlesContent: some View {
        LazyHStack(
            alignment: .top,
            spacing: articlesSpacing
        ) {
            articlesItem
        }
    }
    
    private var articlesItem: some View {
        ForEach(
            articles,
            content: article
        )
    }
    
    private func article(_ article: NT_BlogArticle) -> some View {
        articleContent(article)
            .overlay(alignment: .topTrailing) {
                articleBookmarkButton(article)
            }
            .containerRelativeFrame(
                .horizontal,
                count: containerRelativeFrameCount,
                spacing: articlesSpacing
            )
            .scrollTransition(axis: .horizontal) { content, phase in
                content
                    .scaleEffect(scaleEffect(inPhase: phase))
            }
            .id(article)
    }
    
    private func articleContent(_ article: NT_BlogArticle) -> some View {
        ImageBackgroundTitleSubtitleView(
            image: fullImage(article),
            imageHeight: 224,
            imageAlignment: .top,
            imageCornerRadius: 16,
            title: title(article),
            titleAlignment: .leading,
            subtitle: description(article),
            subtitleAlignment: .leading,
            titleSubtitleAlignment: .leading,
            titleSubtitleMaxWidthAlignment: .leading,
            horizontalAlignment: .leading,
            spacing: spacing
        )
    }
    
    private func articleBookmarkButton(_ article: NT_BlogArticle) -> some View {
        articleBookmarkButtonContent(article)
            .padding(12)
    }
    
    private func articleBookmarkButtonContent(_ article: NT_BlogArticle) -> some View {
        ButtonView(
            title: bookmarkTitle(article),
            icon: Icons.bookmark,
            iconSymbolVariant: bookmarkIconSymbolVariant(article),
            iconFont: .body,
            isIconColorGradient: true,
            iconFrame: bookmarkIconFrame,
            style: .iconOnly,
            verticalPadding: bookmarkPadding,
            horizontalPadding: bookmarkPadding,
            isFullWidth: false,
            backgroundColor: .init(.systemBackground),
            isBackgroundColorGradient: false,
            cornerRadius: 16
        ) {
            bookmark(article)
        }
    }
}

// MARK: - Pagination:

private extension MainEightFeaturedView {
    @ViewBuilder
    private var pagination: some View {
        if !isRegularHorizontalSizeClass {
            paginationContent
        }
    }
    
    private var paginationContent: some View {
        PaginationView(
            current: $currentArticle,
            all: articles
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var currentArticle: NT_BlogArticle? = .example.first
    
    List {
        MainEightFeaturedView(
            articles: NT_BlogArticle.example.filter { $0.isFeatured },
            currentArticle: $currentArticle
        )
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Blog")
    .navigationStack()
}
