import SwiftUI

struct SearchView_Enhanced: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @StateObject private var searchResults = ArticleSearchResultsModel()
    @State private var showNavTitle = false
    @State private var searchText = ""
    @State private var selectedSort: ArticleSortOption = .newest
    @State private var showSearchBar = false
    private var visibleRows: [Article] {
        ArticleLanguageSelection.visible(searchResults.page.articles, language: viewModel.articleLanguage)
    }
    
    var body: some View {
        PodcastMiniPlayerScrollClearance(existingBottomPadding: 80) { clearance in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                    }
                    .frame(height: 0)

                    // Large title - shown only at top
                    if !showNavTitle {
                        Text("Artikler")
                            .font(.largeTitle.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                            .transition(.opacity)
                    }

                    // Search and Sort Controls
                    VStack(spacing: 12) {
                        // Search Bar
                        if showSearchBar {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Søg artikler...", text: $searchText)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("search.controls.query")

                                if !searchText.isEmpty {
                                    Button(action: { searchText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                            .frame(minWidth: 44, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("Ryd søgning")
                                    .accessibilityIdentifier("search.controls.clear")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        searchControls
                    }
                    .padding(.bottom, 8)

                    // Article list
                    if (viewModel.isLoading && visibleRows.isEmpty)
                        || (searchResults.isUpdating && visibleRows.isEmpty) {
                        shimmerPlaceholder
                    } else if viewModel.fetchError != nil && visibleRows.isEmpty {
                        EmptyStateView(
                            icon: "exclamationmark.triangle.fill",
                            title: "Kunne ikke hente artikler",
                            subtitle: "Tjek din internetforbindelse, og prøv igen.",
                            actionTitle: "Prøv igen"
                        ) {
                            viewModel.fetchArticles(forceRefresh: true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, showNavTitle ? 12 : 0)
                    } else {
                        if visibleRows.isEmpty {
                            // Empty state for search results
                            VStack(spacing: 16) {
                                Image(systemName: searchText.isEmpty ? "doc.text" : "magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)

                                Text(LocalizedStringKey(searchText.isEmpty ? "Ingen artikler fundet" : "Ingen resultater"))
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Text(LocalizedStringKey(searchText.isEmpty ? "Prøv at opdatere siden" : "Prøv at søge efter noget andet"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(visibleRows) { article in
                                    Button(action: {
                                        guard viewModel.isVisibleArticle(article) else { return }
                                        navigationCoordinator.navigateToArticle(article, in: .search)
                                    }) {
                                        ArticleRowCompact(article: article)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if article.id != visibleRows.last?.id {
                                        Divider()
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                    }
                                }

                                // Load More Button
                                if searchResults.page.hasMore {
                                    Button(action: searchResults.loadMore) {
                                        HStack {
                                            Text("Indlæs flere artikler")
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                    }
                                    .disabled(searchResults.isUpdating)
                                }
                            }
                            .padding(.top, showNavTitle ? 12 : 0)
                        }
                    }

                    Spacer(minLength: 80)
                }
                .padding(.bottom, clearance)
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            let shouldShow = value < -40
            guard showNavTitle != shouldShow else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showNavTitle = shouldShow
            }
        }
        .refreshable {
            await viewModel.refreshArticles()
        }
        .navigationTitle(LocalizedStringKey(showNavTitle ? "Artikler" : ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            showNavTitle = false
            searchResults.observeContent(articles: viewModel.visibleArticleChanges, authors: viewModel.authorChanges)
            searchResults.updateContent(articles: viewModel.visibleArticles, authors: viewModel.authors)
            searchResults.activate()
        }
        .onDisappear { searchResults.deactivate() }
        .onChange(of: searchText) { _, newValue in
            searchResults.updateQuery(newValue)
        }
        .onChange(of: selectedSort) { _, newValue in
            searchResults.updateSort(newValue)
        }
    }
    
    @ViewBuilder
    private var searchControls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    sortMenu
                    trailingSearchActions
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        sortMenu.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        searchToggle
                        articleCount
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        sortMenu
                        trailingSearchActions
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ArticleSortOption.allCases) { option in
                Button(action: { selectedSort = option }) {
                    HStack {
                        Text(LocalizedStringKey(option.rawValue))
                        if selectedSort == option {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down").font(.caption)
                Text(LocalizedStringKey(selectedSort.rawValue))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 134, maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("Sortér artikler")
        .accessibilityValue(Text(LocalizedStringKey(selectedSort.rawValue)))
        .accessibilityIdentifier("search.controls.sort")
    }

    private var searchToggle: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                showSearchBar.toggle()
                if !showSearchBar { searchText = "" }
            }
        }) {
            Image(systemName: showSearchBar ? "xmark" : "magnifyingglass")
                .foregroundColor(.primary)
                .padding(8)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .background(Color.gray.opacity(0.1))
                .clipShape(Circle())
        }
        .accessibilityLabel(LocalizedStringKey(showSearchBar ? "Luk søgning" : "Vis søgning"))
        .accessibilityIdentifier("search.controls.toggle")
    }

    private var articleCount: some View {
        Text(AppLocalization.articleCount(visibleRows.isEmpty ? 0 : searchResults.page.totalCount,
                                         language: AppLocalization.language(for: locale)))
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityIdentifier("search.controls.count")
    }

    private var trailingSearchActions: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            searchToggle
            articleCount
        }
    }

    private var shimmerPlaceholder: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                HStack(alignment: .top, spacing: 12) {
                    // Thumbnail placeholder
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 60)
                        .cornerRadius(8)
                    
                    // Content placeholder
                    VStack(alignment: .leading, spacing: 4) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 12)
                            .frame(maxWidth: 0.7, alignment: .leading)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 12)
                            .frame(maxWidth: 0.5, alignment: .leading)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                if index < 5 {
                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.top, showNavTitle ? 12 : 0)
    }
}

// MARK: - Preview
struct SearchView_Enhanced_Previews: PreviewProvider {
    static var previews: some View {
        SearchView_Enhanced()
            .environmentObject(ArticleViewModel())
            .environment(\.navigationCoordinator, NavigationCoordinator.shared)
    }
} 
