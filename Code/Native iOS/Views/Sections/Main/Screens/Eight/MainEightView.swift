//
//  MainEightView.swift
//  Native
//

import SwiftUI

struct MainEightView: View {
    
    // MARK: - Properties:
    
    /// An array of the featured articles to display:
    @State var featuredArticles: [NT_BlogArticle] = []
    
    /// Featured article that is currently shown:
    @State var currentFeaturedArticle: NT_BlogArticle? = nil
    
    /// An array of the articles to display:
    @State var articles: [NT_BlogArticle] = []
    
    /// An array of the topics to display:
    @State var topics: [NT_BlogTopic] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    /// Text to search the articles and the topics by that is inputed by the user:
    @State var searchText: String = ""
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .overlay {
                loading
            }
            .overlay {
                nothingHere
            }
            .localizedNavigationTitle(title: "Blog")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer
            )
            .toolbarButton(
                title: "Settings",
                icon: Icons.gearshape,
                iconSymbolVariant: .none,
                font: .body,
                style: .iconOnly,
                placement: .cancellationAction,
                action: showSettings
            )
            .toolbarAvatar()
            .navigationDestination(
                for: NT_BlogArticle.self,
                destination: article
            )
            .navigationDestination(
                for: NT_BlogTopic.self,
                destination: topic
            )
            .animation(
                .default,
                value: searchFeaturedArticles
            )
            .animation(
                .default,
                value: searchArticles
            )
            .animation(
                .default,
                value: searchTopics
            )
            .animation(
                .default,
                value: currentFeaturedArticle
            )
            .animation(
                .default,
                value: isFetching
            )
            .task {
                await fetchData()
            }
            .navigationStack()
    }
}

// MARK: - Empty states:

private extension MainEightView {
    private var loading: some View {
        loadingContent
            .opacity(loadingOpacity)
    }
    
    private var loadingContent: some View {
        LoadingView(
            isShowing: true,
            color: .secondary,
            scale: 1.5
        )
    }
    
    private var nothingHere: some View {
        nothingHereContent
            .opacity(nothingHereOpacity)
    }
    
    private var nothingHereContent: some View {
        EmptyStateView(
            title: "Nothing Here",
            subtitle: "We don't have anything to display here."
        )
    }
}

// MARK: - List:

private extension MainEightView {
    private var list: some View {
        listContent
            .listStyle(.plain)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        featured
        MainEightArticlesView(articles: articles)
        MainEightTopicsView(topics: topics)
    }
}

// MARK: - Featured:

private extension MainEightView {
    private var featured: some View {
        MainEightFeaturedView(
            articles: featuredArticles,
            currentArticle: $currentFeaturedArticle
        )
    }
}

// MARK: - Article and topic:

private extension MainEightView {
    private func article(_ article: NT_BlogArticle) -> some View {
        PlaceholderView(title: title(article))
    }
    
    private func topic(_ topic: NT_BlogTopic) -> some View {
        PlaceholderView(title: title(topic))
    }
}

// MARK: - Preview:

#Preview {
    MainEightView()
}
