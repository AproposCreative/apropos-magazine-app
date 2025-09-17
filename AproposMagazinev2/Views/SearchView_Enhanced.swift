import SwiftUI
import SDWebImageSwiftUI

enum ArticleSortOption: String, CaseIterable, Identifiable {
    case newest = "Nyeste"
    case oldest = "Ældste"
    case titleAZ = "Titel A-Å"
    case titleZA = "Titel Å-A"
    case category = "Kategori"
    
    var id: String { rawValue }
}

struct SearchView_Enhanced: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    @Environment(\.colorScheme) var colorScheme
    @State private var scrollOffset: CGFloat = 0
    @State private var showNavTitle = false
    @State private var searchText = ""
    @State private var selectedSort: ArticleSortOption = .newest
    @State private var showSearchBar = false
    @State private var showSortMenu = false
    
    // Computed properties for filtered and sorted articles
    private var filteredArticles: [Article] {
        if searchText.isEmpty {
            return viewModel.articles
        } else {
            return viewModel.articles.filter { article in
                let title = article.name?.lowercased() ?? ""
                let intro = article.intro?.lowercased() ?? ""
                let author = article.author?.name.lowercased() ?? ""
                let searchQuery = searchText.lowercased()
                return title.contains(searchQuery) || intro.contains(searchQuery) || author.contains(searchQuery)
            }
        }
    }
    
    private var sortedArticles: [Article] {
        let articles = filteredArticles
        
        switch selectedSort {
        case .newest:
            return articles.sorted { ($0.date ?? "") > ($1.date ?? "") }
        case .oldest:
            return articles.sorted { ($0.date ?? "") < ($1.date ?? "") }
        case .titleAZ:
            return articles.sorted { ($0.name ?? "") < ($1.name ?? "") }
        case .titleZA:
            return articles.sorted { ($0.name ?? "") > ($1.name ?? "") }
        case .category:
            return articles.sorted { ($0.topicID ?? "") < ($1.topicID ?? "") }
        }
    }
    
    var body: some View {
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
                            
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Sort and Search Controls
                    HStack(spacing: 12) {
                        // Sort Menu
                        Menu {
                            ForEach(ArticleSortOption.allCases) { option in
                                Button(action: { selectedSort = option }) {
                                    HStack {
                                        Text(option.rawValue)
                                        if selectedSort == option {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.caption)
                                Text(selectedSort.rawValue)
                                    .font(.subheadline)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        Spacer()
                        
                        // Search Toggle Button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showSearchBar.toggle()
                                if !showSearchBar {
                                    searchText = ""
                                }
                            }
                        }) {
                            Image(systemName: showSearchBar ? "xmark" : "magnifyingglass")
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        // Article Count
                        Text("\(sortedArticles.count) artikler")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)

                // Article list
                if viewModel.isLoading {
                    shimmerPlaceholder
                } else if viewModel.fetchError != nil {
                    EmptyStateView(
                        icon: "exclamationmark.triangle.fill",
                        title: "Kunne ikke hente artikler",
                        subtitle: "Tjek din internetforbindelse, og prøv igen.",
                        actionTitle: "Prøv igen"
                    ) {
                        viewModel.fetchArticles()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, showNavTitle ? 12 : 0)
                } else {
                    if sortedArticles.isEmpty {
                        // Empty state for search results
                        VStack(spacing: 16) {
                            Image(systemName: searchText.isEmpty ? "doc.text" : "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            
                            Text(searchText.isEmpty ? "Ingen artikler fundet" : "Ingen resultater")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text(searchText.isEmpty ? "Prøv at opdatere siden" : "Prøv at søge efter noget andet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(sortedArticles) { article in
                                Button(action: {
                                    navigationCoordinator.navigateToArticle(article, in: .search)
                                }) {
                                    ArticleRowCompact(article: article)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if article.id != sortedArticles.last?.id {
                                    Divider()
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                        .padding(.top, showNavTitle ? 12 : 0)
                    }
                }
                
                Spacer(minLength: 80)
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            withAnimation(.easeInOut(duration: 0.2)) {
                showNavTitle = value < -40
            }
        }
        .scrollableModernTopBar(
            title: "Artikler",
            showNavTitle: $showNavTitle,
            showSearchButton: true,
            showMenuButton: false,
            showNotificationButton: true,
            showUserMenuButton: true,
            onSearch: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSearchBar.toggle()
                }
            },
            onMenu: {
                // No menu action needed
            },
            onNotification: {
                // Handle notifications
                print("Notifications tapped")
            },
            onUserMenu: {
                // Handle user menu
                print("User menu tapped")
            }
        )
        .onAppear {
            showNavTitle = false
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
            .environment(\.navigationCoordinator, NavigationCoordinator())
    }
} 
