import SwiftUI

struct SafeFavoriteButton: View {
    let article: Article
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    let onFavorite: ((Article) -> Void)?
    
    init(article: Article, onFavorite: ((Article) -> Void)? = nil) {
        self.article = article
        self.onFavorite = onFavorite
    }
    
    // Safe computed property to check if article is favorite
    private var isArticleFavorite: Bool {
        return viewModel.isFavorite(article)
    }
    
    // Safe action to toggle favorite
    private func safeToggleFavorite() {
        // Add haptic feedback
        HapticManager.shared.lightImpact()
        viewModel.toggleFavorite(for: article)
        onFavorite?(article)
    }
    
    var body: some View {
        Button(action: safeToggleFavorite) {
            ZStack {
                // Fixed size container to prevent layout shifts
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 32, height: 32)
                
                // Icon with consistent sizing
                Image(systemName: isArticleFavorite ? "checkmark" : "plus")
                    .font(.system(size: 16, weight: .medium)) // Consistent font size
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 16, height: 16) // Fixed icon frame size
            }
        }
    }
}

// MARK: - Safe Favorite Button Extension
extension SafeFavoriteButton {
    /// Creates a safe favorite button that handles nil viewModel cases
    static func createSafeFavoriteButton(
        for article: Article,
        onFavorite: ((Article) -> Void)? = nil
    ) -> some View {
        SafeFavoriteButton(article: article, onFavorite: onFavorite)
    }
}

#Preview {
    SafeFavoriteButton(
        article: Article(
            id: "1",
            name: "Test Article",
            slug: "test-article",
            content: "Test content",
            intro: "Test intro",
            stjerne: 4,
            topicID: "topic1",
            date: "2024-01-15"
        ),
        onFavorite: { _ in }
    )
    .environmentObject(ArticleViewModel())
}
