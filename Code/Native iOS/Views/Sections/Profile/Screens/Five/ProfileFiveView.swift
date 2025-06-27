//
//  ProfileFiveView.swift
//  Native
//

import SwiftUI

struct ProfileFiveView: View {
    
    // MARK: - Properties:
    
    /// Author to display the details for:
    @State var author: NT_ProfileAuthor? = nil
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "Profile")
            .toolbarButton(
                title: "Share",
                icon: Icons.squareAndArrowUp,
                iconSymbolVariant: .none,
                font: .body,
                style: .iconOnly,
                action: share
            )
            .navigationDestination(
                for: NT_BlogArticle.self,
                destination: article
            )
            .animation(
                .default,
                value: author
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

// MARK: - Scroll:

private extension ProfileFiveView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    @ViewBuilder
    private var scrollItem: some View {
        if isFetching {
            loading
        } else if isNoAuthor {
            noData
        } else {
            authorOverviewArticles
        }
    }
}

// MARK: - Empty states:

private extension ProfileFiveView {
    private var loading: some View {
        loadingContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var loadingContent: some View {
        LoadingView(
            isShowing: true,
            color: .secondary,
            scale: 1.5
        )
    }
    
    private var noData: some View {
        noDataContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var noDataContent: some View {
        EmptyStateView(
            title: "No Data",
            subtitle: "We don't have any data to display here."
        )
    }
}

// MARK: - Author, overview, and articles:

private extension ProfileFiveView {
    private var authorOverviewArticles: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            authorOverviewArticlesContent
        }
    }
    
    @ViewBuilder
    private var authorOverviewArticlesContent: some View {
        authorContent
        overview
        articles
    }
    
    @ViewBuilder
    private var authorContent: some View {
        if let author {
            ProfileFiveAuthorView(author: author)
        }
    }
    
    @ViewBuilder
    private var overview: some View {
        if let author {
            ProfileFiveOverviewView(author: author)
        }
    }
    
    @ViewBuilder
    private var articles: some View {
        if let author {
            ProfileFiveArticlesView(author: author)
        }
    }
}

// MARK: - Article:

private extension ProfileFiveView {
    private func article(_ article: NT_BlogArticle) -> some View {
        PlaceholderView(title: title(article))
    }
}

// MARK: - Preview:

#Preview {
    ProfileFiveView()
}
