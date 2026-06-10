import Foundation

enum FavoriteArticlesLogic {
    static func isFavorite(articleId: String, in favorites: [Article]) -> Bool {
        guard !articleId.isEmpty else { return false }
        return favorites.contains(where: { $0.id == articleId })
    }

    static func toggledFavorites(for article: Article, current favorites: [Article]) -> [Article] {
        guard let name = article.name, !name.isEmpty, !article.id.isEmpty else {
            return favorites
        }

        if isFavorite(articleId: article.id, in: favorites) {
            return favorites.filter { $0.id != article.id }
        }

        var updated = favorites
        updated.append(article)
        return updated
    }
}
