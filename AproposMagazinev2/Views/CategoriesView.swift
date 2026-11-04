import SwiftUI
import SDWebImageSwiftUI

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
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Text("Kategorier")
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                    if viewModel.isLoading {
                        shimmerPlaceholder
                    } else {
                        VStack(spacing: 0) {
                            ForEach(categories) { cat in
                                Button(action: {
                                    navigationCoordinator.navigateToCategory(cat.name, in: .categories)
                                }) {
                                    LocalizedArticleTaxonomy(cat.name)
                                        .font(.system(size: 34, weight: .bold))
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 18)
                                }
                                .buttonStyle(PlainButtonStyle())

                                if cat.id != categories.last?.id {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .refreshable {
                await viewModel.refreshArticles()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
            return viewModel.visibleArticles.filter { art in
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
                LocalizedArticleTaxonomy(category.name)
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
        .navigationTitle(LocalizedStringKey(category.name))
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
    @State private var imageLoaded = false
    
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
    
    #if DEBUG && targetEnvironment(simulator)
    var fixtureImage: UIImage? = nil
    var onFrame: ((String, CGRect) -> Void)? = nil
    #endif

    var body: some View {
        // Text determines the row height. Artwork is an overlay, so its ideal
        // size cannot expand or collapse a row while the image loads.
        LeadingArticleArtwork(width: 80, spacing: 12, cornerRadius: 8, cornerStyle: .circular) { _ in
            artwork
        } content: {
            HStack(alignment: .bottom, spacing: 12) {
                measured("content") {
                    VStack(alignment: .leading, spacing: 4) {
                        measured("title") {
                            Text(article.name ?? "Article Title")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Text(article.intro.flatMap { $0.isEmpty ? nil : $0 } ?? "Article subtitle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let rating = article.stjerne, rating > 0 {
                            measured("rating") {
                                HStack(spacing: 3) {
                                    ForEach(0..<6, id: \.self) { index in
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(index < min(rating, 6)
                                                ? (colorScheme == .dark ? Color.white : Color.black.opacity(0.92))
                                                : (colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.14)))
                                    }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(min(rating, 6)) ud af 6 stjerner")
                                .accessibilityIdentifier("article.compact.rating." + article.id)
                            }
                        }
                        measured("category") {
                            LocalizedArticleTaxonomy(articleCategories.first ?? "Generelt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .accessibilityHidden(true)
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .observingArtworkFrame { onFrame?("image", $0) }
#endif
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var artwork: some View {
        ZStack {
            ArticleImagePlaceholder(showShimmer: !imageLoaded, cornerRadius: 8)
            #if DEBUG && targetEnvironment(simulator)
            if let fixtureImage {
                Image(uiImage: fixtureImage).resizable().scaledToFill()
            } else {
                remoteImage
            }
            #else
            remoteImage
            #endif
        }
        .onChange(of: article.listThumbnailURL) { _, _ in imageLoaded = false }
    }

    @ViewBuilder private var remoteImage: some View {
        if let url = article.listThumbnailURL {
            WebImage(url: url, options: [.retryFailed, .continueInBackground])
                .onSuccess { _, _, _ in
                    DispatchQueue.main.async { imageLoaded = true }
                }
                .resizable()
                .scaledToFill()
        }
    }

    @ViewBuilder private func measured<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        content().onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame?(name, $0) }
        #else
        content()
        #endif
    }

}

struct CategoriesView_Previews: PreviewProvider {
    static var previews: some View {
        // let vm = ArticleViewModel() - temporarily disabled
        return CategoriesView()
            // .environmentObject(vm) - temporarily disabled
    }
} 
