import SwiftUI
import SDWebImageSwiftUI

struct CategoryListView: View {
    let categoryTitle: String
    let articles: [Article]
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedLayout: LayoutType = .grid
    @StateObject private var paginationManager: PaginationManager
    @State private var scrollOffset: CGFloat = 0
    
    enum LayoutType: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
        case masonry = "Masonry"
    }
    
    init(categoryTitle: String, articles: [Article]) {
        self.categoryTitle = categoryTitle
        self.articles = articles
        self._paginationManager = StateObject(wrappedValue: PaginationManager(articles: articles))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Sticky Header with layout selector
                stickyHeader
                
                // Content with infinite scroll
                RefreshableScrollView(onRefresh: {
                    await refreshContent()
                }) {
                    LazyVStack(spacing: 16) {
                        switch selectedLayout {
                        case .grid:
                            gridLayout
                        case .list:
                            listLayout
                        case .masonry:
                            masonryLayout
                        }
                        
                        // Loading indicator for infinite scroll
                        if paginationManager.isLoadingMore {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Indlæser...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .preference(key: ScrollOffsetKey.self, value: geometry.frame(in: .named("categoryScroll")).minY)
                        }
                    )
                }
                .coordinateSpace(name: "categoryScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { offset in
                    scrollOffset = offset
                    // Auto-load more when reaching the end
                    if offset > 100 && !paginationManager.isLoadingMore && paginationManager.hasMorePages {
                        paginationManager.loadMoreArticles()
                    }
                }
            }
            .background(Color(.systemBackground))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Sticky Header
    private var stickyHeader: some View {
        VStack(spacing: 0) {
            // Main header
            HStack {
                Spacer()
                
                Text(categoryTitle)
                    .font(.custom("SFProDisplay-Bold", size: 24))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Menu {
                    ForEach(LayoutType.allCases, id: \.self) { layout in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedLayout = layout
                            }
                        }) {
                            HStack {
                                Text(layout.rawValue)
                                if selectedLayout == layout {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.title)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color(.systemBackground)
                    .opacity(scrollOffset < -50 ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: scrollOffset)
            )
            
            // Subtle shadow when scrolled
            if scrollOffset < -50 {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 1)
                    .transition(.opacity)
            }
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Grid Layout (Optimized)
    private var gridLayout: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 20),
            GridItem(.flexible(), spacing: 20)
        ], spacing: 20) {
            ForEach(paginationManager.articles, id: \.id) { article in
                NavigationLink(destination: ArticleDetailView(article: article)) {
                    ImprovedGridArticleCard(article: article)
                }
                .buttonStyle(PlainButtonStyle())
                .onAppear {
                    // Preload next batch when approaching end
                    if let index = paginationManager.articles.firstIndex(of: article),
                       index == paginationManager.articles.count - 3 {
                        paginationManager.loadMoreArticles()
                    }
                }
            }
        }
    }
    
    // MARK: - List Layout (Optimized)
    private var listLayout: some View {
        LazyVStack(spacing: 16) {
            ForEach(paginationManager.articles, id: \.id) { article in
                NavigationLink(destination: ArticleDetailView(article: article)) {
                    ListArticleCard(article: article)
                }
                .buttonStyle(PlainButtonStyle())
                .onAppear {
                    // Preload next batch when approaching end
                    if let index = paginationManager.articles.firstIndex(of: article),
                       index == paginationManager.articles.count - 3 {
                        paginationManager.loadMoreArticles()
                    }
                }
            }
        }
    }
    
    // MARK: - Masonry Layout (Optimized)
    private var masonryLayout: some View {
        LazyVStack(spacing: 16) {
            ForEach(Array(paginationManager.articles.enumerated()), id: \.element.id) { index, article in
                NavigationLink(destination: ArticleDetailView(article: article)) {
                    MasonryArticleCard(article: article, index: index)
                }
                .buttonStyle(PlainButtonStyle())
                .onAppear {
                    // Preload next batch when approaching end
                    if index == paginationManager.articles.count - 3 {
                        paginationManager.loadMoreArticles()
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func refreshContent() async {
        paginationManager.refresh()
        // Add a small delay to show refresh animation
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}



// MARK: - Grid Article Card
struct GridArticleCard: View {
    var article: Article
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    
    private var articleCategories: [String] {
        var categories: [String] = []
        
        if let topicID = article.topicID,
           let topic = viewModel.topics.first(where: { $0.id == topicID }) {
            categories.append(topic.name)
        }
        
        if let topicsIDs = article.topicsIDs {
            for topicID in topicsIDs {
                if let topic = viewModel.topics.first(where: { $0.id == topicID }),
                   !categories.contains(topic.name) {
                    categories.append(topic.name)
                }
            }
        }
        
        return categories.isEmpty ? ["Generelt"] : categories
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image
            var mutableArticle = article
            WebImage(url: URL(string: mutableArticle.thumbnailURL))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 200)
                .clipped()
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            
            VStack(alignment: .leading, spacing: 8) {
                // Category
                Text(articleCategories.joined(separator: " | "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Title
                Text(article.name ?? "Titel")
                    .font(.custom("SFProDisplay-Bold", size: 16))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                // Rating (if available)
                if let rating = article.stjerne, rating > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<6) { index in
                            Image(index < rating ? 
                                (colorScheme == .dark ? "DarkStar" : "DimStar") : 
                                (colorScheme == .dark ? "DimStar" : "DarkStar"))
                                .resizable()
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                
                // Author
                if let authorName = article.author?.name {
                    Text(authorName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - List Article Card
struct ListArticleCard: View {
    var article: Article
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    
    private var articleCategories: [String] {
        var categories: [String] = []
        
        if let topicID = article.topicID,
           let topic = viewModel.topics.first(where: { $0.id == topicID }) {
            categories.append(topic.name)
        }
        
        if let topicsIDs = article.topicsIDs {
            for topicID in topicsIDs {
                if let topic = viewModel.topics.first(where: { $0.id == topicID }),
                   !categories.contains(topic.name) {
                    categories.append(topic.name)
                }
            }
        }
        
        return categories.isEmpty ? ["Generelt"] : categories
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Image
            var mutableArticle = article
            WebImage(url: URL(string: mutableArticle.thumbnailURL))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 120)
                .clipped()
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 8) {
                // Category
                Text(articleCategories.joined(separator: " | "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Title
                Text(article.name ?? "Titel")
                    .font(.custom("SFProDisplay-Bold", size: 18))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                // Rating (if available)
                if let rating = article.stjerne, rating > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<6) { index in
                            Image(index < rating ? 
                                (colorScheme == .dark ? "DarkStar" : "DimStar") : 
                                (colorScheme == .dark ? "DimStar" : "DarkStar"))
                                .resizable()
                                .frame(width: 14, height: 14)
                        }
                    }
                }
                
                // Author
                if let authorName = article.author?.name {
                    Text(authorName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Masonry Article Card
struct MasonryArticleCard: View {
    var article: Article
    let index: Int
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    
    private var articleCategories: [String] {
        var categories: [String] = []
        
        if let topicID = article.topicID,
           let topic = viewModel.topics.first(where: { $0.id == topicID }) {
            categories.append(topic.name)
        }
        
        if let topicsIDs = article.topicsIDs {
            for topicID in topicsIDs {
                if let topic = viewModel.topics.first(where: { $0.id == topicID }),
                   !categories.contains(topic.name) {
                    categories.append(topic.name)
                }
            }
        }
        
        return categories.isEmpty ? ["Generelt"] : categories
    }
    
    private var imageHeight: CGFloat {
        // Vary height based on index for masonry effect
        let heights: [CGFloat] = [180, 220, 160, 200, 240, 170, 190, 210]
        return heights[index % heights.count]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image with varying height
            var mutableArticle = article
            WebImage(url: URL(string: mutableArticle.thumbnailURL))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: imageHeight)
                .clipped()
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            
            VStack(alignment: .leading, spacing: 8) {
                // Category
                Text(articleCategories.joined(separator: " | "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Title
                Text(article.name ?? "Titel")
                    .font(.custom("SFProDisplay-Bold", size: 16))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                // Rating (if available)
                if let rating = article.stjerne, rating > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<6) { index in
                            Image(index < rating ? 
                                (colorScheme == .dark ? "DarkStar" : "DimStar") : 
                                (colorScheme == .dark ? "DimStar" : "DarkStar"))
                                .resizable()
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                
                // Author
                if let authorName = article.author?.name {
                    Text(authorName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Improved Grid Article Card
struct ImprovedGridArticleCard: View {
    var article: Article
    @EnvironmentObject var viewModel: ArticleViewModel
    
    private var articleCategories: [String] {
        var categories: [String] = []
        
        if let topicID = article.topicID,
           let topic = viewModel.topics.first(where: { $0.id == topicID }) {
            categories.append(topic.name)
        }
        
        if let topicsIDs = article.topicsIDs {
            for topicID in topicsIDs {
                if let topic = viewModel.topics.first(where: { $0.id == topicID }),
                   !categories.contains(topic.name) {
                    categories.append(topic.name)
                }
            }
        }
        
        return categories.isEmpty ? ["Generelt"] : categories
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image
            var mutableArticle = article
            WebImage(url: URL(string: mutableArticle.thumbnailURL))
                .resizable()
                .aspectRatio(16/9, contentMode: .fill)
                .frame(height: 120)
                .clipped()
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                // Category
                Text(articleCategories.joined(separator: " | ").uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Title
                Text(article.name ?? "Titel")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()

            // Stars (if available)
            if let rating = article.stjerne, rating > 0 {
                HStack(spacing: 2) {
                    ForEach(0..<6) { i in
                        Image(systemName: i < rating ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundColor(i < rating ? .yellow : .gray)
                    }
                }
            }
        }
        .padding()
        .frame(height: 280)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    CategoryListView(categoryTitle: "Musik", articles: [])
        .environmentObject(ArticleViewModel())
}
