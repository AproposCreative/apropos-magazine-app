import Foundation
import SwiftUI

@MainActor
class PaginationManager: ObservableObject {
    @Published var currentPage = 1
    @Published var isLoadingMore = false
    @Published var hasMorePages = true
    @Published var articles: [Article] = []
    
    private let pageSize = 20
    private let allArticles: [Article]
    private var loadedArticles: Set<String> = []
    
    init(articles: [Article]) {
        self.allArticles = articles
        loadInitialPage()
    }
    
    // MARK: - Pagination Logic
    
    func loadInitialPage() {
        currentPage = 1
        articles = Array(allArticles.prefix(pageSize))
        loadedArticles = Set(articles.map { $0.id })
        hasMorePages = allArticles.count > pageSize
    }
    
    func loadMoreArticles() {
        guard !isLoadingMore && hasMorePages else { return }
        
        isLoadingMore = true
        HapticManager.shared.lightImpact()
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.performLoadMore()
        }
    }
    
    private func performLoadMore() {
        let startIndex = currentPage * pageSize
        let endIndex = min(startIndex + pageSize, allArticles.count)
        
        guard startIndex < allArticles.count else {
            hasMorePages = false
            isLoadingMore = false
            return
        }
        
        let newArticles = Array(allArticles[startIndex..<endIndex])
        
        // Filter out already loaded articles
        let uniqueNewArticles = newArticles.filter { !loadedArticles.contains($0.id) }
        
        articles.append(contentsOf: uniqueNewArticles)
        loadedArticles.formUnion(uniqueNewArticles.map { $0.id })
        
        currentPage += 1
        hasMorePages = endIndex < allArticles.count
        isLoadingMore = false
        
        HapticManager.shared.success()
    }
    
    func refresh() {
        loadInitialPage()
        HapticManager.shared.mediumImpact()
    }
    
    // MARK: - Search & Filter Support
    
    func filterArticles(with query: String) {
        let filtered = allArticles.filter { article in
            let title = article.name?.lowercased() ?? ""
            let intro = article.intro?.lowercased() ?? ""
            let content = article.content?.lowercased() ?? ""
            let searchQuery = query.lowercased()
            
            return title.contains(searchQuery) || 
                   intro.contains(searchQuery) || 
                   content.contains(searchQuery)
        }
        
        // Reset pagination for filtered results
        currentPage = 1
        articles = Array(filtered.prefix(pageSize))
        loadedArticles = Set(articles.map { $0.id })
        hasMorePages = filtered.count > pageSize
    }
    
    func filterByCategory(_ category: String) {
        let filtered = allArticles.filter { article in
            article.topicID == category
        }
        
        currentPage = 1
        articles = Array(filtered.prefix(pageSize))
        loadedArticles = Set(articles.map { $0.id })
        hasMorePages = filtered.count > pageSize
    }
    
    func filterByAuthor(_ authorId: String) {
        let filtered = allArticles.filter { article in
            article.authorID == authorId
        }
        
        currentPage = 1
        articles = Array(filtered.prefix(pageSize))
        loadedArticles = Set(articles.map { $0.id })
        hasMorePages = filtered.count > pageSize
    }
    
    func filterByDate(_ dateRange: PaginationDateRange) {
        let filtered = allArticles.filter { article in
            // This would be enhanced with actual publication dates
            // For now, we'll use a simple filter
            return true // Placeholder
        }
        
        currentPage = 1
        articles = Array(filtered.prefix(pageSize))
        loadedArticles = Set(articles.map { $0.id })
        hasMorePages = filtered.count > pageSize
    }
}

// MARK: - Supporting Types

enum PaginationDateRange {
    case today
    case thisWeek
    case thisMonth
    case lastMonth
    case custom(from: Date, to: Date)
    
    var displayName: String {
        switch self {
        case .today: return "I dag"
        case .thisWeek: return "Denne uge"
        case .thisMonth: return "Denne måned"
        case .lastMonth: return "Sidste måned"
        case .custom: return "Tilpasset"
        }
    }
}

// MARK: - SwiftUI Extensions

struct PaginatedListView<Content: View>: View {
    @ObservedObject var paginationManager: PaginationManager
    let content: ([Article]) -> Content
    
    var body: some View {
        LazyVStack(spacing: 0) {
            content(paginationManager.articles)
            
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
            
            if paginationManager.hasMorePages && !paginationManager.isLoadingMore {
                Button(action: {
                    paginationManager.loadMoreArticles()
                }) {
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("Indlæs flere")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding()
                }
            }
        }
        .onAppear {
            // Auto-load more when reaching the end
            if paginationManager.articles.count > 0 {
                let lastArticle = paginationManager.articles.last!
                if paginationManager.articles.firstIndex(of: lastArticle) == paginationManager.articles.count - 3 {
                    paginationManager.loadMoreArticles()
                }
            }
        }
    }
}

// MARK: - Pull to Refresh

struct RefreshableScrollView<Content: View>: View {
    let onRefresh: () async -> Void
    let content: Content
    
    init(onRefresh: @escaping () async -> Void, @ViewBuilder content: () -> Content) {
        self.onRefresh = onRefresh
        self.content = content()
    }
    
    var body: some View {
        ScrollView {
            content
        }
        .refreshable {
            await onRefresh()
        }
    }
}

// MARK: - Infinite Scroll Detection

struct InfiniteScrollDetector: ViewModifier {
    let action: () -> Void
    let threshold: CGFloat
    
    init(action: @escaping () -> Void, threshold: CGFloat = 100) {
        self.action = action
        self.threshold = threshold
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: geometry.frame(in: .named("scroll")).minY)
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                if offset > threshold {
                    action()
                }
            }
    }
}

extension View {
    func infiniteScroll(action: @escaping () -> Void, threshold: CGFloat = 100) -> some View {
        self.modifier(InfiniteScrollDetector(action: action, threshold: threshold))
    }
}

// MARK: - Loading States

struct LoadingStateView: View {
    let state: LoadingState
    
    enum LoadingState {
        case idle
        case loading
        case loaded
        case error(String)
        case empty
    }
    
    var body: some View {
        switch state {
        case .idle:
            EmptyView()
            
        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Indlæser artikler...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
        case .loaded:
            EmptyView()
            
        case .error(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                
                Text("Fejl ved indlæsning")
                    .font(.headline)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Prøv igen") {
                    // Retry action would be passed in
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
        case .empty:
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                
                Text("Ingen artikler fundet")
                    .font(.headline)
                
                Text("Prøv at søge efter noget andet eller tjek senere igen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
