import SwiftUI

// Temporary type aliases removed - using real types now

struct CategoryItem: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: Kind
    
    enum Kind { 
        case topic 
    }
}

struct CategoriesView: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    
    // Build a flat list of categories from what we already have
    private var categories: [CategoryItem] {
        let topics: [CategoryItem] = viewModel.topics.map {
            CategoryItem(id: $0.id, name: $0.name, kind: .topic)
        }
        
        return topics
            .uniqued()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top padding to account for modern top bar
            Spacer()
                .frame(height: 104) // 44 (safe area) + 60 (top bar height)
            
            if viewModel.isLoading {
                shimmerPlaceholder
            } else {
                List(categories) { cat in
                    Button(action: {
                        navigationCoordinator.navigateToCategory(cat.name, in: .categories)
                    }) {
                        Text(cat.name)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.vertical, 14)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12))
                    .listRowSeparator(.visible)
                }
                .listStyle(.plain)
            }
        }
        // .modernTopBar() - temporarily disabled
    }
    
    private var shimmerPlaceholder: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { index in
                HStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 200, height: 24)
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                
                if index < 7 {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 20)
    }
}

// Small helper to dedupe
private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}

struct CategoryArticlesView: View {
    let category: CategoryItem
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var navigationCoordinator: NavigationCoordinator
    @State private var scrollOffset: CGFloat = 0
    @State private var showNavTitle = false
    
    // Filter logic that reuses our existing article array
    private var articles: [Article] {
        switch category.kind {
        case .topic:
            return viewModel.articles.filter { art in
                let id = category.id
                if let t = art.topicID, t == id { return true }
                if let list = art.topicsIDs, list.contains(id) { return true }
                return false
            }
        }
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    SwiftUI.Color.clear
                        // .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY) - temporarily disabled
                }
                .frame(height: 0)

                // Den store overskrift
                Text(category.name)
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // Artikelliste
                if viewModel.isLoading {
                    shimmerPlaceholder
                } else {
                    VStack(spacing: 0) {
                        ForEach(articles) { article in
                            Button(action: {
                                navigationCoordinator.navigateToArticle(article, in: .categories)
                            }) {
                                ArticleRowCompact(article: article)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            if article.id != articles.last?.id {
                                Divider()
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(.top, showNavTitle ? 12 : 0)
                }

                Spacer(minLength: 60)
            }
            .padding(.bottom, 16)
        }
        .coordinateSpace(name: "scroll")
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        // .onAppear - temporarily disabled
    }
    
    private var shimmerPlaceholder: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 60)
                    .cornerRadius(8)
                
                if index < 5 {
                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.top, 12)
    }
}

// Compact row (thumbnail + title + subtitle)
struct ArticleRowCompact: View {
    var article: Article
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    
    // Get categories for this article
    private var articleCategories: [String] {
        var categories: [String] = []
        
        // Add main topic category
        if let topicID = article.topicID,
           let topic = viewModel.topics.first(where: { $0.id == topicID }) {
            categories.append(topic.name)
        }
        
        // Add multi-topic categories if available
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
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            var mutableArticle = article
            let thumbnailURL = mutableArticle.thumbnailURL
            AsyncImage(url: URL(string: thumbnailURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 80, height: 60)
            .clipped()
            .cornerRadius(8)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(article.name ?? "Article Title")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Subtitle/Intro
                if let intro = article.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("Article subtitle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                // Category
                if !articleCategories.isEmpty {
                    Text(articleCategories.first ?? "Generelt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Chevron
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            // Pre-load article data when row appears
            if article.author == nil {
                viewModel.loadFullArticle(with: article.id)
            }
        }
    }
}

struct CategoriesView_Previews: PreviewProvider {
    static var previews: some View {
        // let vm = ArticleViewModel() - temporarily disabled
        return CategoriesView()
            // .environmentObject(vm) - temporarily disabled
    }
} 
