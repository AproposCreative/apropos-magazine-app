import SwiftUI

struct SafeFavoriteButton: View {
    let article: Article
    @EnvironmentObject var viewModel: ArticleViewModel
    let onFavorite: ((Article) -> Void)?
    
    init(article: Article, onFavorite: ((Article) -> Void)? = nil) {
        self.article = article
        self.onFavorite = onFavorite
    }
    
    private func safeToggleFavorite(generation: UUID) {
        guard FavoritesRuntime.model.snapshot.generation == generation else { return }
        HapticManager.shared.lightImpact()
        viewModel.toggleFavorite(for: article)
        onFavorite?(article)
    }
    
    var body: some View {
        ArticleFavoriteControl(model: FavoritesRuntime.model, articleID: article.id,
                               toggle: safeToggleFavorite, retry: viewModel.retryFavorites,
                               requiresAccount: viewModel.accountSaveGate.isGuest && !viewModel.isFavorite(article),
                               onAccountRequired: { viewModel.toggleFavorite(for: article) })
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
